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
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use IPC::System::Simple qw(capture);

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
my $iPort = 5432;                           # Port to run Postgres on
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
    my $strUserParam = shift;
    my $strPasswordParam = shift;
    my $strHostParam = shift;
    my $strDatabaseParam = shift;
    my $bRaiseError = shift;

    # Log Connection
    &log("   DB: connect user ${strUser}, database ${strDatabase}");

    # Disconnect user session
    pgDisconnect();

    # Connect to the db
    return DBI->connect('dbi:Pg:dbname=' .
                        (defined($strDatabaseParam) ? $strDatabaseParam : $strDatabase) .
                        ";port=${iPort};host=" .
                        (defined($strHostParam) ? $strHostParam : '/tmp'),
                        defined($strUserParam) ? $strUserParam : $strUser,
                        defined($strPasswordParam) ? $strPasswordParam : undef,
                        {AutoCommit => true,
                         RaiseError => defined($bRaiseError) ? $bRaiseError : true});
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
# pgQuery
################################################################################
# sub pgQuery
# {
#     my $strSql = shift;
#
#     # Log the statement
#     &log("  SQL: ${strSql}");
#
#     # Execute the statement
#     my $hStatement = $hDb->prepare($strSql);
#
#     $hStatement->execute();
#     $hStatement->finish();
# }

################################################################################
# pgExecute
################################################################################
sub pgExecute
{
    my $strSql = shift;
    my $hDbParam = shift;

    # Log the statement
    &log("  SQL: ${strSql}");

    # Execute the statement
    ($hDbParam ? $hDbParam : $hDb)->do($strSql);
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

    commandExecute("echo 'local all all trust' > ${strPath}/pg_hba.conf");
    commandExecute("echo 'host all all 127.0.0.1/32 md5' >> ${strPath}/pg_hba.conf");
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
                   " -c unix_socket_directories='/tmp'" .
                   "\" -D ${strPath} -l ${strPath}/postgresql.log -w -s");

    # Connect user session
    $hDb = pgConnect();
}

################################################################################
# pgPsql
################################################################################
sub pgPsql
{
    my $strOption = shift;
    my $bSuppressError = shift;

    commandExecute("${strPgSqlBin}/psql -p ${iPort} " .
                   "${strOption} ${strDatabase}", $bSuppressError);
}

################################################################################
# Main
################################################################################
my $strBasePath = dirname(dirname(abs_path($0)));
my $strAnalyzeExe = "${strBasePath}/bin/pgaudit_analyze";

# Drop the old cluster, build the code, and create a new cluster
pgDrop();
pgCreate();
pgStart();

# Load the audit schema
pgPsql("-f ${strBasePath}/sql/audit.sql");

# Verify that successful logons are logged
#-------------------------------------------------------------------------------
my $strUser1 = 'test1';
pgExecute("create user ${strUser1} with password '${strUser1}'");

pgConnect($strUser1, 'bogus', '127.0.0.1', undef, false);
pgConnect($strUser1, 'still-bogus', '127.0.0.1', undef, false);

commandExecute("${strAnalyzeExe} $strTestPath/pg_log");

# Stop the database
if (!$bNoCleanup)
{
    pgDrop();
}
