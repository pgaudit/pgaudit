#!/usr/bin/perl
################################################################################
# test.pl - pgaudit log analyze regression tests
################################################################################

################################################################################
# Perl includes
################################################################################
use strict;
use warnings FATAL => qw(all);
use Carp;

use Getopt::Long;
use Pod::Usage;
use DBI;
use Cwd qw(abs_path);
use IPC::System::Simple qw(capture system);

################################################################################
# Constants
################################################################################
use constant
{
    true  => 1,
    false => 0
};

################################################################################
# Command line parameters
################################################################################
my $strPgSqlBin = '/usr/local/pgsql/bin';   # Path of PG binaries to use for
                                            # this test
my $strTestPath = 'test';                   # Path where testing will occur
my $strUser = getpwuid($>);                 # PG user name
my $strDatabase = 'postgres';               # PG database
my $iPort = 6000;                           # Port to run Postgres on
my $bHelp = false;                          # Display help
my $bQuiet = false;                         # Supress output except for errors
my $bNoCleanup = false;                     # Cleanup database on exit

GetOptions ('q|quiet' => \$bQuiet,
            'no-cleanup' => \$bNoCleanup,
            'help' => \$bHelp,
            'pgsql-bin=s' => \$strPgSqlBin,
            'test-path=s' => \$strTestPath)
    or pod2usage(2);

# Display version and exit if requested
if ($bHelp)
{
    print 'pgaudit log analyzer regression test\n\n';
    pod2usage();

    exit 0;
}

################################################################################
# Global variables
################################################################################
my $hDb;                    # Connection to Postgres

################################################################################
# commandExecute
################################################################################
sub commandExecute
{
    my $strCommand = shift;
    my $bSuppressError = shift;

    # Set default
    $bSuppressError = defined($bSuppressError) ? $bSuppressError : false;

    # Run the command
    my $iResult = system($strCommand);

    if ($iResult != 0 && !$bSuppressError)
    {
        confess "command '${strCommand}' failed with error ${iResult}";
    }
}

################################################################################
# log
################################################################################
sub log
{
    my $strMessage = shift;
    my $bError = shift;

    # Set default
    $bError = defined($bError) ? $bError : false;

    if (!$bQuiet)
    {
        print "${strMessage}\n";
    }

    if ($bError)
    {
        exit 1;
    }
}

################################################################################
# pgConnect
################################################################################
sub pgConnect
{
    # Log Connection
    &log("   DB: connect user ${strUser}, database ${strDatabase}");

    # Disconnect user session
    pgDisconnect();

    # Connect to the db
    $hDb = DBI->connect("dbi:Pg:dbname=${strDatabase};port=${iPort};host=/tmp",
                        $strUser, undef,
                        {AutoCommit => 1, RaiseError => 1});
}

################################################################################
# pgDisconnect
################################################################################
sub pgDisconnect
{
    # Connect to the db (whether it is local or remote)
    if (defined($hDb))
    {
        $hDb->disconnect;
        undef($hDb);
    }
}

################################################################################
# pgExecute
################################################################################
sub pgExecute
{
    my $strSql = shift;

    # Log the statement
    &log("  SQL: ${strSql}");

    # Execute the statement
    my $hStatement = $hDb->prepare($strSql);

    print "${strSql};\n";

    $hStatement->execute();
    $hStatement->finish();
}

################################################################################
# pgExecuteOnly
################################################################################
sub pgExecuteOnly
{
    my $strSql = shift;

    # Log the statement
    &log("  SQL: ${strSql}");

    print "${strSql};\n";

    # Execute the statement
    $hDb->do($strSql);
}

################################################################################
# pgDrop
################################################################################
sub pgDrop
{
    my $strPath = shift;

    # Set default
    $strPath = defined($strPath) ? $strPath : $strTestPath;

    # Stop the cluster
    pgStop(true, $strPath);

    # Remove the directory
    commandExecute("rm -rf ${strTestPath}");
}

################################################################################
# pgCreate
################################################################################
sub pgCreate
{
    my $strPath = shift;

    # Set default
    $strPath = defined($strPath) ? $strPath : $strTestPath;

    commandExecute("${strPgSqlBin}/initdb -D ${strPath} -U ${strUser}" .
                   ' -A trust > /dev/null');
}

################################################################################
# pgStop
################################################################################
sub pgStop
{
    my $bImmediate = shift;
    my $strPath = shift;

    # Set default
    $strPath = defined($strPath) ? $strPath : $strTestPath;
    $bImmediate = defined($bImmediate) ? $bImmediate : false;

    # Disconnect user session
    pgDisconnect();

    # If postmaster process is running then stop the cluster
    if (-e $strPath . '/postmaster.pid')
    {
        commandExecute("${strPgSqlBin}/pg_ctl stop -D ${strPath} -w -s -m " .
                      ($bImmediate ? 'immediate' : 'fast'));
    }
}

################################################################################
# pgStart
################################################################################
sub pgStart
{
    my $strPath = shift;

    # Set default
    $strPath = defined($strPath) ? $strPath : $strTestPath;

    # Make sure postgres is not running
    if (-e $strPath . '/postmaster.pid')
    {
        confess "${strPath}/postmaster.pid exists, cannot start";
    }

    # Start the cluster
    commandExecute("${strPgSqlBin}/pg_ctl start -o \"" .
                   " -c port=${iPort}" .
                   " -c unix_socket_directories='/tmp'" .
                   " -c shared_preload_libraries='pgaudit'" .
                   " -c log_min_messages=notice" .
                   " -c log_error_verbosity=verbose" .
                   " -c log_connections=on" .
                   " -c log_destination=csvlog" .
                   " -c logging_collector=on" .
                   " -c log_rotation_age=1" .
                   " -c log_connections=on" .
                   "\" -D ${strPath} -l ${strPath}/postgresql.log -w -s");

    # Connect user session
    pgConnect();
}

################################################################################
# Main
################################################################################
# Drop the old cluster, build the code, and create a new cluster
pgDrop();
pgCreate();
pgStart();

# Stop the database
if (!$bNoCleanup)
{
    pgDrop();
}
