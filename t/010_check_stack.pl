# Regression test for pgaudit issue #298 ("pgaudit stack is not empty" on
# FETCH).  When a client fetches from a cursor using the extended query
# protocol with a row limit (the JDBC setFetchSize(n>0) scenario), the FETCH
# runs in a named portal that is left *suspended*.  pgaudit pushes a FetchStmt
# onto its audit stack for that portal, and because the portal outlives the
# statement the entry lingers.  The next top-level utility statement (here a
# CLOSE) walks the stack in pgaudit_ProcessUtility_hook() and, before the fix,
# raised "pgaudit stack is not empty".
#
# libpq (and therefore psql, pg_regress and DBD::Pg) always sends Execute with
# a row limit of 0, so it can never suspend a portal and cannot reproduce this.
# We therefore speak the v3 frontend/backend protocol directly over the socket.

use strict;
use warnings FATAL => 'all';
use Test::More;

use IO::Socket::UNIX;
use IO::Socket::INET;
use PostgreSQL::Test::Cluster;

# ---------------------------------------------------------------------------
# Minimal v3 wire protocol helpers
# ---------------------------------------------------------------------------

# Build a typed frontend message (type byte + Int32 length + payload).
sub fe_msg
{
    my ($type, $payload) = @_;
    $payload = '' unless defined $payload;
    return $type . pack('N', 4 + length($payload)) . $payload;
}

# StartupMessage has no type byte and carries the protocol version.
sub startup_msg
{
    my (%params) = @_;
    my $payload = pack('N', 3 << 16);    # protocol 3.0
    $payload .= "$_\0$params{$_}\0" for sort keys %params;
    $payload .= "\0";
    return pack('N', 4 + length($payload)) . $payload;
}

sub query_msg { return fe_msg('Q', "$_[0]\0"); }
sub parse_msg { return fe_msg('P', "$_[0]\0$_[1]\0" . pack('n', 0)); }    # name, sql, 0 params

sub bind_msg
{
    my ($portal, $stmt) = @_;
    # portal, stmt, 0 param formats, 0 params, 0 result formats
    return fe_msg('B', "$portal\0$stmt\0" . pack('n', 0) . pack('n', 0) . pack('n', 0));
}

sub execute_msg { return fe_msg('E', "$_[0]\0" . pack('N', $_[1])); }    # portal, max rows
sub sync_msg    { return fe_msg('S'); }
sub terminate_msg { return fe_msg('X'); }

# Read exactly $n bytes or die.
sub read_n
{
    my ($sock, $n) = @_;
    my $buf = '';
    while (length($buf) < $n)
    {
        my $r = sysread($sock, my $chunk, $n - length($buf));
        die "unexpected EOF from server" if !defined $r || $r == 0;
        $buf .= $chunk;
    }
    return $buf;
}

# Read one backend message, returning (type, payload).
sub read_msg
{
    my ($sock) = @_;
    my $type = read_n($sock, 1);
    my $len = unpack('N', read_n($sock, 4));
    my $payload = $len > 4 ? read_n($sock, $len - 4) : '';
    return ($type, $payload);
}

# Extract the human-readable message (field 'M') from an ErrorResponse payload.
sub error_text
{
    my ($payload) = @_;
    for my $field (split /\0/, $payload)
    {
        return substr($field, 1) if length($field) && substr($field, 0, 1) eq 'M';
    }
    return '';
}

# Drain messages until ReadyForQuery ('Z'); return (\@types, \@error_texts).
sub read_until_ready
{
    my ($sock) = @_;
    my (@types, @errors);
    while (1)
    {
        my ($type, $payload) = read_msg($sock);
        push @types, $type;
        push @errors, error_text($payload) if $type eq 'E';
        last if $type eq 'Z';
    }
    return (\@types, \@errors);
}

# ---------------------------------------------------------------------------
# Bring up a node with pgaudit and connect over a raw socket
# ---------------------------------------------------------------------------

my $node = PostgreSQL::Test::Cluster->new('audit');
$node->init;
$node->append_conf('postgresql.conf', "shared_preload_libraries = 'pgaudit'");
$node->append_conf('postgresql.conf', "pgaudit.log = 'all'");
# Keep audit output on stderr so $node->log_contains() can see it.
$node->append_conf('postgresql.conf', "logging_collector = off");
$node->start;

# The node uses trust auth, so no password handshake is required.
my $host = $node->host;
my $sock;
if (substr($host, 0, 1) eq '/')
{
    $sock = IO::Socket::UNIX->new(Peer => "$host/.s.PGSQL." . $node->port)
      or die "could not connect to unix socket: $!";
}
else
{
    $sock = IO::Socket::INET->new(PeerHost => $host, PeerPort => $node->port)
      or die "could not connect to $host: $!";
}
$sock->autoflush(1);
binmode($sock);

print $sock startup_msg(user => 'postgres', database => 'postgres');
read_until_ready($sock);

# Open an explicit transaction and declare a cursor that returns several rows.
print $sock query_msg('BEGIN');
read_until_ready($sock);
print $sock query_msg('DECLARE c CURSOR FOR SELECT generate_series(1, 5)');
read_until_ready($sock);

# Extended protocol: FETCH ALL FROM c, but Execute with a row limit of 1.
# A named portal plus a non-zero row limit leaves the portal suspended,
# exactly as JDBC's setFetchSize(n>0) does.
print $sock parse_msg('', 'FETCH ALL FROM c');
print $sock bind_msg('p_fetch', '');
print $sock execute_msg('p_fetch', 1);
print $sock sync_msg();
my ($fetch_types, $fetch_errors) = read_until_ready($sock);

# Sanity check: if the portal was not suspended ('s') the bug conditions were
# not reproduced and a green result below would be meaningless.
ok((grep { $_ eq 's' } @$fetch_types),
    'FETCH leaves the portal suspended (PortalSuspended received)')
  or diag('fetch reply messages: ' . join(',', @$fetch_types));
is_deeply($fetch_errors, [], 'FETCH itself raised no error')
  or diag('fetch errors: ' . join(' | ', @$fetch_errors));

# CLOSE is a top-level utility statement.  With the suspended FETCH still on
# the audit stack this is where pgaudit raised "pgaudit stack is not empty".
print $sock query_msg('CLOSE c');
my ($close_types, $close_errors) = read_until_ready($sock);

is_deeply($close_errors, [],
    'CLOSE after a suspended FETCH does not raise "pgaudit stack is not empty"')
  or diag('close errors: ' . join(' | ', @$close_errors));

print $sock query_msg('COMMIT');
read_until_ready($sock);
print $sock terminate_msg();
close($sock);

# pgaudit should still have logged the FETCH (auditing is not broken by the fix).
ok($node->log_contains(qr/AUDIT:.*,FETCH,/), 'FETCH was audit logged');

$node->stop;

done_testing();
