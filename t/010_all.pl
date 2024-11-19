use strict;
use warnings FATAL => 'all';
use Test::More;

use DBI;
use PostgreSQL::Test::Cluster;

# Initialize and start cluster
my $node = PostgreSQL::Test::Cluster->new('main');
$node->init;
$node->append_conf('postgresql.conf', "shared_preload_libraries = 'pgaudit'");
$node->start;

# Connect to cluster
my $db = DBI->connect(
    "dbi:Pg:dbname=postgres;port=" . $node->port() . ";host=" . $node->host(),
    "postgres", undef,
    {AutoCommit => 0, RaiseError => 1, PrintError => 1});

# !!! REPLACE WITH REAL TESTS
is($db->do("select 1"), 1);

# Disconnect and stop cluster
undef($db);
$node->stop;

done_testing();
