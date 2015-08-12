#!/usr/bin/perl
################################################################################
# test.pl - pg_audit Unit Tests
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
use IPC::System::Simple qw(capture);

################################################################################
# Constants
################################################################################
use constant
{
	true  => 1,
	false => 0
};

use constant
{
	CONTEXT_GLOBAL   => 'GLOBAL',
	CONTEXT_DATABASE => 'DATABASE',
	CONTEXT_ROLE	 => 'ROLE'
};

use constant
{
	CLASS			=> 'CLASS',

	CLASS_DDL		=> 'DDL',
	CLASS_FUNCTION	=> 'FUNCTION',
	CLASS_MISC		=> 'MISC',
	CLASS_PARAMETER => 'PARAMETER',
	CLASS_READ		=> 'READ',
	CLASS_ROLE		=> 'ROLE',
	CLASS_WRITE		=> 'WRITE',

	CLASS_ALL		=> 'ALL',
	CLASS_NONE		=> 'NONE'
};

use constant
{
	COMMAND						=> 'COMMAND',
	COMMAND_LOG					=> 'COMMAND_LOG',

	COMMAND_ANALYZE					=> 'ANALYZE',
	COMMAND_ALTER_AGGREGATE			=> 'ALTER AGGREGATE',
	COMMAND_ALTER_COLLATION			=> 'ALTER COLLATION',
	COMMAND_ALTER_CONVERSION		=> 'ALTER CONVERSION',
	COMMAND_ALTER_DATABASE			=> 'ALTER DATABASE',
	COMMAND_ALTER_ROLE				=> 'ALTER ROLE',
	COMMAND_ALTER_ROLE_SET			=> 'ALTER ROLE SET',
	COMMAND_ALTER_TABLE				=> 'ALTER TABLE',
	COMMAND_ALTER_TABLE_COLUMN		=> 'ALTER TABLE COLUMN',
	COMMAND_ALTER_TABLE_INDEX		=> 'ALTER TABLE INDEX',
	COMMAND_BEGIN					=> 'BEGIN',
	COMMAND_CLOSE					=> 'CLOSE CURSOR',
	COMMAND_COMMIT					=> 'COMMIT',
	COMMAND_COPY					=> 'COPY',
	COMMAND_COPY_TO					=> 'COPY TO',
	COMMAND_COPY_FROM				=> 'COPY FROM',
	COMMAND_CREATE_AGGREGATE		=> 'CREATE AGGREGATE',
	COMMAND_CREATE_COLLATION		=> 'CREATE COLLATION',
	COMMAND_CREATE_CONVERSION		=> 'CREATE CONVERSION',
	COMMAND_CREATE_DATABASE			=> 'CREATE DATABASE',
	COMMAND_CREATE_INDEX			=> 'CREATE INDEX',
	COMMAND_DEALLOCATE				=> 'DEALLOCATE',
	COMMAND_DECLARE_CURSOR			=> 'DECLARE CURSOR',
	COMMAND_DO						=> 'DO',
	COMMAND_DISCARD_ALL				=> 'DISCARD ALL',
	COMMAND_CREATE_FUNCTION			=> 'CREATE FUNCTION',
	COMMAND_CREATE_ROLE				=> 'CREATE ROLE',
	COMMAND_CREATE_SCHEMA			=> 'CREATE SCHEMA',
	COMMAND_CREATE_TABLE			=> 'CREATE TABLE',
	COMMAND_CREATE_TABLE_AS			=> 'CREATE TABLE AS',
	COMMAND_CREATE_TABLE_INDEX		=> 'CREATE TABLE INDEX',
	COMMAND_DROP_DATABASE			=> 'DROP DATABASE',
	COMMAND_DROP_SCHEMA				=> 'DROP SCHEMA',
	COMMAND_DROP_TABLE				=> 'DROP TABLE',
	COMMAND_DROP_TABLE_CONSTRAINT	=> 'DROP TABLE CONSTRAINT',
	COMMAND_DROP_TABLE_INDEX		=> 'DROP TABLE INDEX',
	COMMAND_DROP_TABLE_TOAST		=> 'DROP TABLE TOAST',
	COMMAND_DROP_TABLE_TYPE			=> 'DROP TABLE TYPE',
	COMMAND_EXECUTE					=> 'EXECUTE',
	COMMAND_EXECUTE_READ			=> 'EXECUTE READ',
	COMMAND_EXECUTE_WRITE			=> 'EXECUTE WRITE',
	COMMAND_EXECUTE_FUNCTION		=> 'EXECUTE FUNCTION',
	COMMAND_EXPLAIN					=> 'EXPLAIN',
	COMMAND_FETCH					=> 'FETCH',
	COMMAND_GRANT					=> 'GRANT',
	COMMAND_INSERT					=> 'INSERT',
	COMMAND_PREPARE					=> 'PREPARE',
	COMMAND_PREPARE_READ			=> 'PREPARE READ',
	COMMAND_PREPARE_WRITE			=> 'PREPARE WRITE',
	COMMAND_REVOKE					=> 'REVOKE',
	COMMAND_SELECT					=> 'SELECT',
	COMMAND_SET						=> 'SET',
	COMMAND_UPDATE					=> 'UPDATE'
};

use constant
{
	TYPE					=> 'TYPE',
	TYPE_NONE				=> '',

	TYPE_AGGREGATE			=> 'AGGREGATE',
	TYPE_COLLATION			=> 'COLLATION',
	TYPE_CONVERSION			=> 'CONVERSION',
	TYPE_SCHEMA				=> 'SCHEMA',
	TYPE_FUNCTION			=> 'FUNCTION',
	TYPE_INDEX				=> 'INDEX',
	TYPE_TABLE				=> 'TABLE',
	TYPE_TABLE_COLUMN		=> 'TABLE COLUMN',
	TYPE_TABLE_CONSTRAINT	=> 'TABLE CONSTRAINT',
	TYPE_TABLE_TOAST		=> 'TABLE TOAST',
	TYPE_TYPE				=> 'TYPE'
};

use constant
{
	NAME			=> 'NAME',
	SESSION			=> 'SESSION'
};

################################################################################
# Command line parameters
################################################################################
my $strPgSqlBin = '../../../../bin/bin';	# Path of PG binaries to use for
											# this test
my $strTestPath = '../../../../data';		# Path where testing will occur
my $iDefaultPort = 6000;					# Default port to run Postgres on
my $bHelp = false;							# Display help
my $bQuiet = false;							# Supress output except for errors
my $bNoCleanup = false;						# Cleanup database on exit

GetOptions ('q|quiet' => \$bQuiet,
			'no-cleanup' => \$bNoCleanup,
			'help' => \$bHelp,
			'pgsql-bin=s' => \$strPgSqlBin,
			'test-path=s' => \$strTestPath)
	or pod2usage(2);

# Display version and exit if requested
if ($bHelp)
{
	print 'pg_audit unit test\n\n';
	pod2usage();

	exit 0;
}

################################################################################
# Global variables
################################################################################
my $hDb;					# Connection to Postgres
my $strLogExpected = '';	# The expected log compared with grepping AUDIT
							# entries from the postgres log.

my $strDatabase = 'postgres';	# Connected database (modified by PgSetDatabase)
my $strUser = 'postgres';		# Connected user (modified by PgSetUser)
my $strAuditRole = 'audit';		# Role to use for auditing

my %oAuditLogHash;				# Hash to store pg_audit.log GUCS
my %oAuditGrantHash;			# Hash to store pg_audit grants

# pg_audit.log setting
my $strCurrentAuditLog;		# setting Postgres was started with
my $strTemporaryAuditLog;	# setting that was set hot

# pg_audit.log_relation setting
my $bCurrentAuditLogRelation = false;	# setting Postgres was started with
my $bTemporaryAuditLogRelation = $bCurrentAuditLogRelation; # hot setting

################################################################################
# Stores the mapping between commands, classes, and types
################################################################################
my %oCommandHash =
(
	&COMMAND_ANALYZE => {&CLASS => &CLASS_MISC, &TYPE => &TYPE_NONE},
	&COMMAND_ALTER_AGGREGATE => {&CLASS => &CLASS_DDL,
		&TYPE => &TYPE_AGGREGATE},
	&COMMAND_ALTER_DATABASE => {&CLASS => &CLASS_DDL, &TYPE => &TYPE_NONE},
	&COMMAND_ALTER_COLLATION => {&CLASS => &CLASS_DDL,
		&TYPE => &TYPE_COLLATION},
	&COMMAND_ALTER_CONVERSION => {&CLASS => &CLASS_DDL,
		&TYPE => &TYPE_CONVERSION},
	&COMMAND_ALTER_ROLE => {&CLASS => &CLASS_ROLE, &TYPE => &TYPE_NONE},
	&COMMAND_ALTER_ROLE_SET => {&CLASS => &CLASS_ROLE, &TYPE => &TYPE_NONE,
		&COMMAND => &COMMAND_ALTER_ROLE},
	&COMMAND_ALTER_TABLE => {&CLASS => &CLASS_DDL, &TYPE => &TYPE_TABLE},
	&COMMAND_ALTER_TABLE_COLUMN => {&CLASS => &CLASS_DDL,
		&TYPE => &TYPE_TABLE_COLUMN, &COMMAND => &COMMAND_ALTER_TABLE},
	&COMMAND_ALTER_TABLE_INDEX => {&CLASS => &CLASS_DDL, &TYPE => &TYPE_INDEX,
		&COMMAND => &COMMAND_ALTER_TABLE},
	&COMMAND_BEGIN => {&CLASS => &CLASS_MISC, &TYPE => &TYPE_NONE},
	&COMMAND_CLOSE => {&CLASS => &CLASS_MISC, &TYPE => &TYPE_NONE},
	&COMMAND_COMMIT => {&CLASS => &CLASS_MISC, &TYPE => &TYPE_NONE},
	&COMMAND_COPY_FROM => {&CLASS => &CLASS_WRITE, &TYPE => &TYPE_NONE,
		&COMMAND => &COMMAND_COPY},
	&COMMAND_COPY_TO => {&CLASS => &CLASS_READ, &TYPE => &TYPE_NONE,
		&COMMAND => &COMMAND_COPY},
	&COMMAND_CREATE_AGGREGATE => {&CLASS => &CLASS_DDL,
		&TYPE => &TYPE_AGGREGATE},
	&COMMAND_CREATE_CONVERSION => {&CLASS => &CLASS_DDL,
		&TYPE => &TYPE_CONVERSION},
	&COMMAND_CREATE_COLLATION => {&CLASS => &CLASS_DDL,
		&TYPE => &TYPE_COLLATION},
	&COMMAND_CREATE_DATABASE => {&CLASS => &CLASS_DDL, &TYPE => &TYPE_NONE},
	&COMMAND_DEALLOCATE => {&CLASS => &CLASS_MISC, &TYPE => &TYPE_NONE},
	&COMMAND_DECLARE_CURSOR => {&CLASS => &CLASS_READ, &TYPE => &TYPE_NONE},
	&COMMAND_DO => {&CLASS => &CLASS_FUNCTION, &TYPE => &TYPE_NONE},
	&COMMAND_DISCARD_ALL => {&CLASS => &CLASS_MISC, &TYPE => &TYPE_NONE},
	&COMMAND_CREATE_FUNCTION => {&CLASS => &CLASS_DDL, &TYPE => &TYPE_FUNCTION},
	&COMMAND_CREATE_INDEX => {&CLASS => &CLASS_DDL, &TYPE => &TYPE_INDEX},
	&COMMAND_CREATE_ROLE => {&CLASS => &CLASS_ROLE, &TYPE => &TYPE_NONE},
	&COMMAND_CREATE_SCHEMA => {&CLASS => &CLASS_DDL, &TYPE => &TYPE_SCHEMA},
	&COMMAND_CREATE_TABLE => {&CLASS => &CLASS_DDL, &TYPE => &TYPE_TABLE},
	&COMMAND_CREATE_TABLE_AS => {&CLASS => &CLASS_DDL, &TYPE => &TYPE_TABLE},
	&COMMAND_CREATE_TABLE_INDEX => {&CLASS => &CLASS_DDL, &TYPE => &TYPE_INDEX,
		&COMMAND => &COMMAND_CREATE_TABLE},
	&COMMAND_DROP_DATABASE => {&CLASS => &CLASS_DDL, &TYPE => &TYPE_NONE},
	&COMMAND_DROP_SCHEMA => {&CLASS => &CLASS_DDL, &TYPE => &TYPE_NONE},
	&COMMAND_DROP_TABLE => {&CLASS => &CLASS_DDL, &TYPE => &TYPE_TABLE},
	&COMMAND_DROP_TABLE_CONSTRAINT => {&CLASS => &CLASS_DDL,
		&TYPE => &TYPE_TABLE_CONSTRAINT, &COMMAND => &COMMAND_DROP_TABLE},
	&COMMAND_DROP_TABLE_INDEX => {&CLASS => &CLASS_DDL, &TYPE => &TYPE_INDEX,
		&COMMAND => &COMMAND_DROP_TABLE},
	&COMMAND_DROP_TABLE_TOAST => {&CLASS => &CLASS_DDL,
		&TYPE => &TYPE_TABLE_TOAST, &COMMAND => &COMMAND_DROP_TABLE},
	&COMMAND_DROP_TABLE_TYPE => {&CLASS => &CLASS_DDL, &TYPE => &TYPE_TYPE,
		&COMMAND => &COMMAND_DROP_TABLE},
	&COMMAND_EXECUTE_READ => {&CLASS => &CLASS_READ, &TYPE => &TYPE_NONE,
		&COMMAND => &COMMAND_EXECUTE},
	&COMMAND_EXECUTE_WRITE => {&CLASS => &CLASS_WRITE, &TYPE => &TYPE_NONE,
		&COMMAND => &COMMAND_EXECUTE},
	&COMMAND_EXECUTE_FUNCTION => {&CLASS => &CLASS_FUNCTION,
		&TYPE => &TYPE_FUNCTION, &COMMAND => &COMMAND_EXECUTE},
	&COMMAND_EXPLAIN => {&CLASS => &CLASS_MISC, &TYPE => &TYPE_NONE},
	&COMMAND_FETCH => {&CLASS => &CLASS_MISC, &TYPE => &TYPE_NONE},
	&COMMAND_GRANT => {&CLASS => &CLASS_ROLE, &TYPE => &TYPE_TABLE},
	&COMMAND_PREPARE_READ => {&CLASS => &CLASS_READ, &TYPE => &TYPE_NONE,
		&COMMAND => &COMMAND_PREPARE},
	&COMMAND_PREPARE_WRITE => {&CLASS => &CLASS_WRITE, &TYPE => &TYPE_NONE,
		&COMMAND => &COMMAND_PREPARE},
	&COMMAND_INSERT => {&CLASS => &CLASS_WRITE, &TYPE => &TYPE_NONE},
	&COMMAND_REVOKE => {&CLASS => &CLASS_ROLE, &TYPE => &TYPE_TABLE},
	&COMMAND_SELECT => {&CLASS => &CLASS_READ, &TYPE => &TYPE_NONE},
	&COMMAND_SET => {&CLASS => &CLASS_MISC, &TYPE => &TYPE_NONE},
	&COMMAND_UPDATE => {&CLASS => &CLASS_WRITE, &TYPE => &TYPE_NONE}
);

################################################################################
# CommandExecute
################################################################################
sub CommandExecute
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
# ArrayToString
################################################################################
sub ArrayToString
{
	my @stryArray = @_;

	my $strResult = '';

	for (my $iIndex = 0; $iIndex < @stryArray; $iIndex++)
	{
		if ($iIndex != 0)
		{
			$strResult .= ', ';
		}

		$strResult .= $stryArray[$iIndex];
	}

	return $strResult;
}

################################################################################
# BuildModule
################################################################################
sub BuildModule
{
	capture('cd ..;make');
	CommandExecute("cp ../pg_audit.so" .
				   " ${strPgSqlBin}/../lib/postgresql");
	CommandExecute("cp ../pg_audit.control" .
				   " ${strPgSqlBin}/../share/postgresql/extension");
	CommandExecute("cp ../pg_audit--1.0.0.sql" .
				   " ${strPgSqlBin}/../share/postgresql/extension");
}

################################################################################
# PgConnect
################################################################################
sub PgConnect
{
	my $iPort = shift;

	# Set default
	$iPort = defined($iPort) ? $iPort : $iDefaultPort;

	# Log Connection
	&log("   DB: connect user ${strUser}, database ${strDatabase}");

	# Disconnect user session
	PgDisconnect();
	
	print "\\connect ${strDatabase} ${strUser}\n\n";

	# Connect to the db
	$hDb = DBI->connect("dbi:Pg:dbname=${strDatabase};port=${iPort};host=/tmp",
						$strUser, undef,
						{AutoCommit => 1, RaiseError => 1});
}

################################################################################
# PgDisconnect
################################################################################
sub PgDisconnect
{
	# Connect to the db (whether it is local or remote)
	if (defined($hDb))
	{
		$hDb->disconnect;
		undef($hDb);
	}
}

################################################################################
# PgExecute
################################################################################
sub PgExecute
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
# PgExecuteOnly
################################################################################
sub PgExecuteOnly
{
	my $strSql = shift;

	# Log the statement
	&log("  SQL: ${strSql}");

	print "${strSql};\n";

	# Execute the statement
	$hDb->do($strSql);
}

################################################################################
# PgSetDatabase
################################################################################
sub PgSetDatabase
{
	my $strDatabaseParam = shift;

	# Stop and start the database to reset pgconf entries
	PgStop();
	PgStart();

	# Execute the statement
	$strDatabase = $strDatabaseParam;
	PgConnect();
}

################################################################################
# PgSetUser
################################################################################
sub PgSetUser
{
	my $strUserParam = shift;

	$strUser = $strUserParam;

	my $bRestart = false;

	# Check log setting
	if ((defined($strTemporaryAuditLog) && !defined($strCurrentAuditLog)) ||
		(defined($strCurrentAuditLog) && !defined($strTemporaryAuditLog)) ||
		$strCurrentAuditLog ne $strTemporaryAuditLog)
	{
		$strCurrentAuditLog = $strTemporaryAuditLog;
		$bRestart = true;
	}

	# Check log setting
	if ($bCurrentAuditLogRelation != $bTemporaryAuditLogRelation)
	{
		$bCurrentAuditLogRelation = $bTemporaryAuditLogRelation;
		$bRestart = true;
	}

	# Stop and start the database to reset pgconf entries
	if ($bRestart)
	{
		PgStop();
		PgStart();
	}
	else
	{
		# Execute the statement
		PgConnect();
	}
}

################################################################################
# SaveString
################################################################################
sub SaveString
{
	my $strFile = shift;
	my $strString = shift;

	# Open the file for writing
	my $hFile;

	open($hFile, '>', $strFile)
		or confess "unable to open ${strFile}";

	if ($strString ne '')
	{
		syswrite($hFile, $strString)
			or confess "unable to write to ${strFile}: $!";
	}

	close($hFile);
}

################################################################################
# PgLogExecute
################################################################################
sub PgLogExecute
{
	my $strCommand = shift;
	my $strSql = shift;
	my $oData = shift;
	my $bExecute = shift;
	my $bWait = shift;
	my $bLogSql = shift;
	my $strParameter = shift;
	my $bExpectError = shift;

	# Set defaults
	$bExecute = defined($bExecute) ? $bExecute : true;
	$bWait = defined($bWait) ? $bWait : true;
	$bLogSql = defined($bLogSql) ? $bLogSql : true;

	if ($bExecute)
	{
		eval
		{
			PgExecuteOnly($strSql);
		};

		if ($@ && !$bExpectError)
		{
			confess $@;
		}
	}

	PgLogExpect($strCommand, $bLogSql ? $strSql : '', $strParameter, $oData);

	if ($bWait)
	{
		PgLogWait();
	}
}

################################################################################
# QuoteCSV
################################################################################
sub QuoteCSV
{
	my $strCSV = shift;

	if (defined($strCSV) &&
		(index($strCSV, ',') >= 0 || index($strCSV, '"') > 0 ||
		 index($strCSV, "\n") > 0 || index($strCSV, "\r") >= 0))
	{
		$strCSV =~ s/"/""/g;
		$strCSV = "\"${strCSV}\"";
	}

	return $strCSV;
}

################################################################################
# PgLogExpect
################################################################################
sub PgLogExpect
{
	my $strCommand = shift;
	my $strSql = shift;
	my $strParameter = shift;
	my $oData = shift;

	# If oData is false then no logging
	if (defined($oData) && ref($oData) eq '' && !$oData)
	{
		return;
	}

	# Quote SQL if needs to be quoted
	$strSql = QuoteCSV($strSql);

	if (defined($strParameter))
	{
		$strSql .= ",${strParameter}";
	}

	# Has a table list been passed?
	my $bTableList = ref($oData) eq 'ARRAY' &&
	                 ($strCommand eq COMMAND_SELECT ||
		              $oCommandHash{$strCommand}{&CLASS} eq CLASS_WRITE);

	# Log based on session
	my $bSessionRelation = false;
	
	if (PgShouldLog($strCommand))
	{
		# Make sure class is defined
		my $strClass = $oCommandHash{$strCommand}{&CLASS};

		if (!defined($strClass))
		{
			confess "class is not defined for command ${strCommand}";
		}

		# Make sure object type is defined
		my $strObjectType = $oCommandHash{$strCommand}{&TYPE};

		if (!defined($strObjectType))
		{
			confess "object type is not defined for command ${strCommand}";
		}

		# Check for command override
		my $strCommandLog = $strCommand;

		if ($oCommandHash{$strCommand}{&COMMAND})
		{
			$strCommandLog = $oCommandHash{$strCommand}{&COMMAND};
		}

		my $strObjectName = '';

		if (defined($oData) && ref($oData) ne 'ARRAY')
		{
			$strObjectName = QuoteCSV($oData);
		}

		if (!($bTableList && $bCurrentAuditLogRelation))
		{
			my $strLog .= "SESSION,${strClass},${strCommandLog}," .
						  "${strObjectType},${strObjectName},${strSql}";
			&log("AUDIT: ${strLog}");

			$strLogExpected .= "${strLog}\n";
		}
	}

	# Log based on grants
	if ($bTableList)
	{
		foreach my $oTableHash (@{$oData})
		{
			my $strObjectName = QuoteCSV(${$oTableHash}{&NAME});
			my $strCommandLog = ${$oTableHash}{&COMMAND};
			my $strClass = $oCommandHash{$strCommandLog}{&CLASS};
			my $strObjectType = ${$oTableHash}{&TYPE};
			my $strLogType;

			if (defined($oAuditGrantHash{$strAuditRole}
										{$strObjectName}{$strCommandLog}) &&
				!defined(${$oTableHash}{&SESSION}))
			{
				$strCommandLog = defined(${$oTableHash}{&COMMAND_LOG}) ?
					${$oTableHash}{&COMMAND_LOG} : $strCommandLog;
				$strClass = $oCommandHash{$strCommandLog}{&CLASS};

				my $strLog .= "OBJECT,${strClass},${strCommandLog}," .
							  "${strObjectType},${strObjectName},${strSql}";

				&log("AUDIT: ${strLog}");
				$strLogExpected .= "${strLog}\n";
			}

			if ($bCurrentAuditLogRelation)
			{
				my $strLog .= "SESSION,${strClass},${strCommandLog}," .
							  "${strObjectType},${strObjectName},${strSql}";

				&log("AUDIT: ${strLog}");
				$strLogExpected .= "${strLog}\n";
			}
		}

		$oData = undef;
	}
}

################################################################################
# PgShouldLog
################################################################################
sub PgShouldLog
{
	my $strCommand = shift;

	# Make sure class is defined
	my $strClass = $oCommandHash{$strCommand}{&CLASS};

	if (!defined($strClass))
	{
		confess "class is not defined for command ${strCommand}";
	}

	# Check logging for the role
	my $bLog = undef;

	if (defined($oAuditLogHash{&CONTEXT_ROLE}{$strUser}))
	{
		$bLog = $oAuditLogHash{&CONTEXT_ROLE}{$strUser}{$strClass};
	}

	# Else check logging for the db
	elsif (defined($oAuditLogHash{&CONTEXT_DATABASE}{$strDatabase}))
	{
		$bLog = $oAuditLogHash{&CONTEXT_DATABASE}{$strDatabase}{$strClass};
	}

	# Else check logging for global
	elsif (defined($oAuditLogHash{&CONTEXT_GLOBAL}{&CONTEXT_GLOBAL}))
	{
		$bLog = $oAuditLogHash{&CONTEXT_GLOBAL}{&CONTEXT_GLOBAL}{$strClass};
	}

	return defined($bLog) ? true : false;
}

################################################################################
# PgLogWait
################################################################################
sub PgLogWait
{
	my $strLogActual;

	# Run in an eval block since grep returns 1 when nothing was found
	eval
	{
		$strLogActual = capture("grep 'LOG:  AUDIT: '" .
								" ${strTestPath}/postgresql.log");
	};

	# If an error was returned, continue if it was 1, otherwise confess
	if ($@)
	{
		my $iExitStatus = $? >> 8;

		if ($iExitStatus != 1)
		{
			confess "grep returned ${iExitStatus}";
		}

		$strLogActual = '';
	}

	# Strip the AUDIT and timestamp from the actual log
	$strLogActual =~ s/prefix LOG:  AUDIT\: //g;
	$strLogActual =~ s/SESSION,[0-9]+,[0-9]+,/SESSION,/g;
	$strLogActual =~ s/OBJECT,[0-9]+,[0-9]+,/OBJECT,/g;

	# Save the logs
	SaveString("${strTestPath}/audit.actual", $strLogActual);
	SaveString("${strTestPath}/audit.expected", $strLogExpected);

	CommandExecute("diff ${strTestPath}/audit.expected" .
				   " ${strTestPath}/audit.actual");
}

################################################################################
# PgDrop
################################################################################
sub PgDrop
{
	my $strPath = shift;

	# Set default
	$strPath = defined($strPath) ? $strPath : $strTestPath;

	# Stop the cluster
	PgStop(true, $strPath);

	# Remove the directory
	CommandExecute("rm -rf ${strTestPath}");
}

################################################################################
# PgCreate
################################################################################
sub PgCreate
{
	my $strPath = shift;

	# Set default
	$strPath = defined($strPath) ? $strPath : $strTestPath;

	CommandExecute("${strPgSqlBin}/initdb -D ${strPath} -U ${strUser}" .
				   ' -A trust > /dev/null');
}

################################################################################
# PgStop
################################################################################
sub PgStop
{
	my $bImmediate = shift;
	my $strPath = shift;

	# Set default
	$strPath = defined($strPath) ? $strPath : $strTestPath;
	$bImmediate = defined($bImmediate) ? $bImmediate : false;

	# Disconnect user session
	PgDisconnect();

	# If postmaster process is running then stop the cluster
	if (-e $strPath . '/postmaster.pid')
	{
		CommandExecute("${strPgSqlBin}/pg_ctl stop -D ${strPath} -w -s -m " .
					  ($bImmediate ? 'immediate' : 'fast'));
	}
}

################################################################################
# PgStart
################################################################################
sub PgStart
{
	my $iPort = shift;
	my $strPath = shift;

	# Set default
	$iPort = defined($iPort) ? $iPort : $iDefaultPort;
	$strPath = defined($strPath) ? $strPath : $strTestPath;

	# Make sure postgres is not running
	if (-e $strPath . '/postmaster.pid')
	{
		confess "${strPath}/postmaster.pid exists, cannot start";
	}

	# Start the cluster
	CommandExecute("${strPgSqlBin}/pg_ctl start -o \"" .
				   "-c port=${iPort}" .
				   " -c unix_socket_directories='/tmp'" .
				   " -c shared_preload_libraries='pg_audit'" .
				   " -c log_min_messages=debug1" .
				   " -c log_line_prefix='prefix '" .
				   " -c log_statement=all" .
				   (defined($strCurrentAuditLog) ?
					   " -c pg_audit.log='${strCurrentAuditLog}'" : '') .
				   ' -c pg_audit.log_relation=' .
				       ($bCurrentAuditLogRelation ? 'on' : 'off') .
				   " -c pg_audit.role='${strAuditRole}'" .
				   " -c log_connections=on" .
				   "\" -D ${strPath} -l ${strPath}/postgresql.log -w -s");

	# Connect user session
	PgConnect();
}

################################################################################
# PgAuditLogSet
################################################################################
sub PgAuditLogSet
{
	my $strContext = shift;
	my $strName = shift;
	my @stryClass = @_;

	# Create SQL to set the GUC
	my $strCommand;
	my $strSql;

	if ($strContext eq CONTEXT_GLOBAL)
	{
		$strCommand = COMMAND_SET;
		$strSql = "set pg_audit.log = '" .
				  ArrayToString(@stryClass) . "'";
		$strTemporaryAuditLog = ArrayToString(@stryClass);
	}
	elsif ($strContext eq CONTEXT_ROLE)
	{
		$strCommand = COMMAND_ALTER_ROLE_SET;
		$strSql = "alter role ${strName} set pg_audit.log = '" .
				  ArrayToString(@stryClass) . "'";
	}
	else
	{
		confess "unable to set pg_audit.log for context ${strContext}";
	}

	# Reset the audit log
	if ($strContext eq CONTEXT_GLOBAL)
	{
		delete($oAuditLogHash{$strContext});
		$strName = CONTEXT_GLOBAL;
	}
	else
	{
		delete($oAuditLogHash{$strContext}{$strName});
	}

	# Store all the classes in the hash and build the GUC
	foreach my $strClass (@stryClass)
	{
		if ($strClass eq CLASS_ALL)
		{
			$oAuditLogHash{$strContext}{$strName}{&CLASS_DDL} = true;
			$oAuditLogHash{$strContext}{$strName}{&CLASS_FUNCTION} = true;
			$oAuditLogHash{$strContext}{$strName}{&CLASS_MISC} = true;
			$oAuditLogHash{$strContext}{$strName}{&CLASS_READ} = true;
			$oAuditLogHash{$strContext}{$strName}{&CLASS_ROLE} = true;
			$oAuditLogHash{$strContext}{$strName}{&CLASS_WRITE} = true;
		}

		if (index($strClass, '-') == 0)
		{
			$strClass = substr($strClass, 1);

			delete($oAuditLogHash{$strContext}{$strName}{$strClass});
		}
		else
		{
			$oAuditLogHash{$strContext}{$strName}{$strClass} = true;
		}
	}

	PgLogExecute($strCommand, $strSql);
}

################################################################################
# PgAuditLogRelationSet
################################################################################
sub PgAuditLogRelationSet
{
	my $strContext = shift;
	my $strName = shift;
	my $bLogRelation = shift;

	# Create SQL to set the GUC
	my $strCommand;
	my $strSql;

	if ($strContext eq CONTEXT_GLOBAL)
	{
		$strCommand = COMMAND_SET;
		$strSql = 'set pg_audit.log_relation';
		$bTemporaryAuditLogRelation = $bLogRelation;
	}
	elsif ($strContext eq CONTEXT_ROLE)
	{
		$strCommand = COMMAND_ALTER_ROLE_SET;
		$strSql = "alter role ${strName} set pg_audit.log_relation";
		$bCurrentAuditLogRelation = $bLogRelation;
		$bTemporaryAuditLogRelation = $bLogRelation;
	}
	else
	{
		confess "unable to set pg_audit.log_relation for context ${strContext}";
	}

	PgLogExecute($strCommand, $strSql . ' = ' .
	             ($bLogRelation ? 'on' : 'off'));
}

################################################################################
# PgAuditGrantSet
################################################################################
sub PgAuditGrantSet
{
	my $strRole = shift;
	my $strPrivilege = shift;
	my $strObject = shift;
	my $strColumn = shift;

	# Create SQL to set the grant
	PgLogExecute(COMMAND_GRANT, "GRANT " .
								(defined($strColumn) ?
									lc(${strPrivilege}) ." (${strColumn})" :
									uc(${strPrivilege})) .
								" ON TABLE ${strObject} TO ${strRole} ");

	$oAuditGrantHash{$strRole}{$strObject}{$strPrivilege} = true;
}

################################################################################
# PgAuditGrantReset
################################################################################
sub PgAuditGrantReset
{
	my $strRole = shift;
	my $strPrivilege = shift;
	my $strObject = shift;
	my $strColumn = shift;

	# Create SQL to set the grant
	PgLogExecute(COMMAND_REVOKE, "REVOKE  " . uc(${strPrivilege}) .
				 (defined($strColumn) ? " (${strColumn})" : '') .
				 " ON TABLE ${strObject} FROM ${strRole} ");

	delete($oAuditGrantHash{$strRole}{$strObject}{$strPrivilege});
}

################################################################################
# Main
################################################################################
my @oyTable;	   # Store table info for select, insert, update, delete
my $strSql;		# Hold Sql commands

# Drop the old cluster, build the code, and create a new cluster
PgDrop();
BuildModule();
PgCreate();
PgStart();

PgExecute("create extension pg_audit");

# Create test users and the audit role
PgExecute("create user user1");
PgExecute("create user user2");
PgExecute("create role ${strAuditRole}");

PgAuditLogSet(CONTEXT_GLOBAL, undef, (CLASS_DDL, CLASS_ROLE));

PgAuditLogSet(CONTEXT_ROLE, 'user2', (CLASS_READ, CLASS_WRITE));

# User1 follows the global log settings
PgSetUser('user1');

$strSql = 'CREATE  TABLE  public.test (id pg_catalog.int4   )' .
		  '  WITH (oids=OFF)  ';
PgLogExecute(COMMAND_CREATE_TABLE, $strSql, 'public.test');
PgLogExecute(COMMAND_SELECT, 'select * from test');

$strSql = 'drop table test';
PgLogExecute(COMMAND_DROP_TABLE, $strSql, 'public.test');

PgSetUser('user2');
PgLogExecute(COMMAND_CREATE_TABLE,
			 'create table test2 (id int)', 'public.test2');
PgAuditGrantSet($strAuditRole, &COMMAND_SELECT, 'public.test2');
PgLogExecute(COMMAND_CREATE_TABLE,
			 'create table test3 (id int)', 'public.test2');

# Catalog select should not log
PgLogExecute(COMMAND_SELECT, 'select * from pg_class limit 1',
							   false);

# Multi-table select
@oyTable = ({&NAME => 'public.test3', &TYPE => &TYPE_TABLE,
			 &COMMAND => &COMMAND_SELECT},
			{&NAME => 'public.test2', &TYPE => &TYPE_TABLE,
			 &COMMAND => &COMMAND_SELECT});
PgLogExecute(COMMAND_SELECT, 'select * from test3, test2',
							   \@oyTable);

# Various CTE combinations
PgAuditGrantSet($strAuditRole, &COMMAND_INSERT, 'public.test3');

@oyTable = ({&NAME => 'public.test3', &TYPE => &TYPE_TABLE,
			 &COMMAND => &COMMAND_INSERT},
			{&NAME => 'public.test2', &TYPE => &TYPE_TABLE,
			 &COMMAND => &COMMAND_SELECT});
PgLogExecute(COMMAND_INSERT,
			 'with cte as (select id from test2)' .
			 ' insert into test3 select id from cte',
			 \@oyTable);

@oyTable = ({&NAME => 'public.test2', &TYPE => &TYPE_TABLE,
			 &COMMAND => &COMMAND_INSERT},
			{&NAME => 'public.test3', &TYPE => &TYPE_TABLE,
			 &COMMAND => &COMMAND_INSERT});
PgLogExecute(COMMAND_INSERT,
			 'with cte as (insert into test3 values (1) returning id)' .
			 ' insert into test2 select id from cte',
			 \@oyTable);

PgAuditGrantSet($strAuditRole, &COMMAND_UPDATE, 'public.test2');

@oyTable = ({&NAME => 'public.test3', &TYPE => &TYPE_TABLE,
			 &COMMAND => &COMMAND_INSERT},
			{&NAME => 'public.test2', &TYPE => &TYPE_TABLE,
			 &COMMAND => &COMMAND_UPDATE});
PgLogExecute(COMMAND_INSERT,
			 'with cte as (update test2 set id = 1 returning id)' .
			 ' insert into test3 select id from cte',
			 \@oyTable);

@oyTable = ({&NAME => 'public.test3', &TYPE => &TYPE_TABLE,
			 &COMMAND => &COMMAND_UPDATE},
			{&NAME => 'public.test2', &TYPE => &TYPE_TABLE,
			 &COMMAND => &COMMAND_INSERT},
			{&NAME => 'public.test2', &TYPE => &TYPE_TABLE,
			 &COMMAND => &COMMAND_SELECT, &COMMAND_LOG => &COMMAND_INSERT});
PgLogExecute(COMMAND_UPDATE,
			 'with cte as (insert into test2 values (1) returning id)' .
			 ' update test3 set id = cte.id' .
			 ' from cte where test3.id <> cte.id',
			 \@oyTable);

PgSetUser('postgres');
PgAuditLogSet(CONTEXT_ROLE, 'user2', (CLASS_NONE));
PgSetUser('user2');

# Column-based audits
PgLogExecute(COMMAND_CREATE_TABLE,
			 'create table test4 (id int, name text)', 'public.test4');
PgAuditGrantSet($strAuditRole, COMMAND_SELECT, 'public.test4', 'name');
PgAuditGrantSet($strAuditRole, COMMAND_UPDATE, 'public.test4', 'id');
PgAuditGrantSet($strAuditRole, COMMAND_INSERT, 'public.test4', 'name');

# Select
@oyTable = ();
PgLogExecute(COMMAND_SELECT, 'select id from public.test4',
							  \@oyTable);

@oyTable = ({&NAME => 'public.test4', &TYPE => &TYPE_TABLE,
			 &COMMAND => &COMMAND_SELECT});
PgLogExecute(COMMAND_SELECT, 'select name from public.test4',
							  \@oyTable);

# Insert
@oyTable = ();
PgLogExecute(COMMAND_INSERT, 'insert into public.test4 (id) values (1)',
							   \@oyTable);

@oyTable = ({&NAME => 'public.test4', &TYPE => &TYPE_TABLE,
			 &COMMAND => &COMMAND_INSERT});
PgLogExecute(COMMAND_INSERT, "insert into public.test4 (name) values ('test')",
							  \@oyTable);

# Update
@oyTable = ();
PgLogExecute(COMMAND_UPDATE, "update public.test4 set name = 'foo'",
							   \@oyTable);

@oyTable = ({&NAME => 'public.test4', &TYPE => &TYPE_TABLE,
			 &COMMAND => &COMMAND_UPDATE});
PgLogExecute(COMMAND_UPDATE, "update public.test4 set id = 1",
							  \@oyTable);

@oyTable = ({&NAME => 'public.test4', &TYPE => &TYPE_TABLE,
			&COMMAND => &COMMAND_SELECT, &COMMAND_LOG => &COMMAND_UPDATE});
PgLogExecute(COMMAND_UPDATE,
			 "update public.test4 set name = 'foo' where name = 'bar'",
			 \@oyTable);

# Drop test tables
PgLogExecute(COMMAND_DROP_TABLE, "drop table test2", 'public.test2');
PgLogExecute(COMMAND_DROP_TABLE, "drop table test3", 'public.test3');
PgLogExecute(COMMAND_DROP_TABLE, "drop table test4", 'public.test4');


# Make sure there are no more audit events pending in the postgres log
PgLogWait();

# Create some email friendly tests.  These first tests are session logging only.
PgSetUser('postgres');

&log("\nExamples:");

&log("\nSession Audit:\n");

PgAuditLogSet(CONTEXT_GLOBAL, undef, (CLASS_DDL, CLASS_READ));

PgSetUser('user1');

$strSql = 'CREATE  TABLE  public.account (id pg_catalog.int4   ,' .
		  ' name pg_catalog.text   COLLATE pg_catalog."default", ' .
		  'password pg_catalog.text   COLLATE pg_catalog."default", '.
		  'description pg_catalog.text   COLLATE pg_catalog."default")  '.
		  'WITH (oids=OFF)  ';
PgLogExecute(COMMAND_CREATE_TABLE, $strSql, 'public.account');
PgLogExecute(COMMAND_SELECT,
			 'select * from account');
PgLogExecute(COMMAND_INSERT,
			 "insert into account (id, name, password, description)" .
			 " values (1, 'user1', 'HASH1', 'blah, blah')");
&log("AUDIT: <nothing logged>");

# Now tests for object logging
&log("\nObject Audit:\n");

PgSetUser('postgres');
PgAuditLogSet(CONTEXT_GLOBAL, undef, (CLASS_NONE));
PgExecute("set pg_audit.role = 'audit'");
PgSetUser('user1');

PgAuditGrantSet($strAuditRole, &COMMAND_SELECT, 'public.account', 'password');

@oyTable = ();
PgLogExecute(COMMAND_SELECT, 'select id, name from account',
							  \@oyTable);
&log("AUDIT: <nothing logged>");

@oyTable = ({&NAME => 'public.account', &TYPE => &TYPE_TABLE,
			 &COMMAND => &COMMAND_SELECT});
PgLogExecute(COMMAND_SELECT, 'select password from account',
							  \@oyTable);

PgAuditGrantSet($strAuditRole, &COMMAND_UPDATE,
				'public.account', 'name, password');

@oyTable = ();
PgLogExecute(COMMAND_UPDATE, "update account set description = 'yada, yada'",
							  \@oyTable);
&log("AUDIT: <nothing logged>");

@oyTable = ({&NAME => 'public.account', &TYPE => &TYPE_TABLE,
			 &COMMAND => &COMMAND_UPDATE});
PgLogExecute(COMMAND_UPDATE, "update account set password = 'HASH2'",
							  \@oyTable);

# Now tests for session/object logging
&log("\nSession/Object Audit:\n");

PgSetUser('postgres');
PgAuditLogRelationSet(CONTEXT_ROLE, 'user1', true);
PgAuditLogSet(CONTEXT_ROLE, 'user1', (CLASS_READ, CLASS_WRITE));
PgSetUser('user1');

PgLogExecute(COMMAND_CREATE_TABLE,
			 'create table account_role_map (account_id int, role_id int)',
			 'public.account_role_map');
PgAuditGrantSet($strAuditRole, &COMMAND_SELECT, 'public.account_role_map');

@oyTable = ({&NAME => 'public.account', &TYPE => &TYPE_TABLE,
			 &COMMAND => &COMMAND_SELECT},
			{&NAME => 'public.account_role_map', &TYPE => &TYPE_TABLE,
			 &COMMAND => &COMMAND_SELECT});
PgLogExecute(COMMAND_SELECT,
			 'select account.password, account_role_map.role_id from account' .
			 ' inner join account_role_map' .
			 ' on account.id = account_role_map.account_id',
			 \@oyTable);

@oyTable = ({&NAME => 'public.account', &TYPE => &TYPE_TABLE,
			 &COMMAND => &COMMAND_SELECT});
PgLogExecute(COMMAND_SELECT, 'select password from account',
							  \@oyTable);

@oyTable = ({&NAME => 'public.account', &TYPE => &TYPE_TABLE,
		     &COMMAND => &COMMAND_UPDATE, &SESSION => true});
PgLogExecute(COMMAND_UPDATE, "update account set description = 'yada, yada'",
							  \@oyTable);
&log("AUDIT: <nothing logged>");

@oyTable = ({&NAME => 'public.account', &TYPE => &TYPE_TABLE,
			 &COMMAND => &COMMAND_SELECT, &COMMAND_LOG => &COMMAND_UPDATE});
PgLogExecute(COMMAND_UPDATE,
			 "update account set description = 'yada, yada'" .
			 " where password = 'HASH2'",
			 \@oyTable);

@oyTable = ({&NAME => 'public.account', &TYPE => &TYPE_TABLE,
			 &COMMAND => &COMMAND_UPDATE});
PgLogExecute(COMMAND_UPDATE, "update account set password = 'HASH2'",
							  \@oyTable);

							  # Test all sql commands
&log("\nExhaustive Command Tests:\n");

PgSetUser('postgres');

PgAuditLogRelationSet(CONTEXT_ROLE, 'user1', false);
PgAuditLogSet(CONTEXT_GLOBAL, undef, (CLASS_ALL));
PgLogExecute(COMMAND_SET, "set pg_audit.role = 'audit'");

PgLogExecute(COMMAND_DO, "do \$\$\ begin raise notice 'test'; end; \$\$;");

$strSql = 'CREATE SCHEMA  test ';
PgLogExecute(COMMAND_CREATE_SCHEMA, $strSql, 'test');

# Test COPY
PgLogExecute(COMMAND_COPY_TO,
			 "COPY pg_class to '" . abs_path($strTestPath) . "/class.out'");

$strSql = 'CREATE  TABLE  test.pg_class  WITH (oids=OFF)   AS SELECT relname,' .
		  ' relnamespace, reltype, reloftype, relowner, relam, relfilenode, ' .
		  'reltablespace, relpages, reltuples, relallvisible, reltoastrelid, ' .
		  'relhasindex, relisshared, relpersistence, relkind, relnatts, ' .
		  'relchecks, relhasoids, relhaspkey, relhasrules, relhastriggers, ' .
		  'relhassubclass, relrowsecurity, relispopulated, relreplident, ' .
		  'relfrozenxid, relminmxid, relacl, reloptions ' .
		  'FROM pg_catalog.pg_class ';
PgLogExecute(COMMAND_INSERT, $strSql, undef, true, false);
PgLogExecute(COMMAND_CREATE_TABLE_AS, $strSql, 'test.pg_class', false, true);

$strSql = "COPY test.pg_class from '" . abs_path($strTestPath) . "/class.out'";
PgLogExecute(COMMAND_INSERT, $strSql);
#PgLogExecute(COMMAND_COPY_FROM, $strSql, undef, false, true);

# Test prepared SELECT
PgLogExecute(COMMAND_PREPARE_READ,
			 'PREPARE pgclassstmt (oid) as select *' .
			 ' from pg_class where oid = $1');
PgLogExecute(COMMAND_EXECUTE_READ,
			 'EXECUTE pgclassstmt (1)');
PgLogExecute(COMMAND_DEALLOCATE,
			 'DEALLOCATE pgclassstmt');

# Test cursor
PgLogExecute(COMMAND_BEGIN,
			 'BEGIN');
PgLogExecute(COMMAND_DECLARE_CURSOR,
			 'DECLARE ctest SCROLL CURSOR FOR SELECT * FROM pg_class');
PgLogExecute(COMMAND_FETCH,
			 'FETCH NEXT FROM ctest');
PgLogExecute(COMMAND_CLOSE,
			 'CLOSE ctest');
PgLogExecute(COMMAND_COMMIT,
			 'COMMIT');

# Test prepared INSERT
$strSql = 'CREATE  TABLE  test.test_insert (id pg_catalog.int4   )  ' .
		  'WITH (oids=OFF)  ';
PgLogExecute(COMMAND_CREATE_TABLE, $strSql, 'test.test_insert');

$strSql = 'PREPARE pgclassstmt (oid) as insert into test.test_insert (id) ' .
		  'values ($1)';
PgLogExecute(COMMAND_PREPARE_WRITE, $strSql);
PgLogExecute(COMMAND_INSERT, $strSql, undef, false, false, undef, "1");

$strSql = 'EXECUTE pgclassstmt (1)';
PgLogExecute(COMMAND_EXECUTE_WRITE, $strSql, undef, true, true);

# Create a table with a primary key
$strSql = 'CREATE  TABLE  public.test (id pg_catalog.int4   , ' .
		  'name pg_catalog.text   COLLATE pg_catalog."default", description ' .
		  'pg_catalog.text   COLLATE pg_catalog."default", CONSTRAINT ' .
		  'test_pkey PRIMARY KEY (id))  WITH (oids=OFF)  ';
PgLogExecute(COMMAND_CREATE_INDEX, $strSql, 'public.test_pkey', true, false);
PgLogExecute(COMMAND_CREATE_TABLE, $strSql, 'public.test', false, false);
PgLogExecute(COMMAND_CREATE_TABLE_INDEX, $strSql, 'public.test_pkey', false, true);

PgLogExecute(COMMAND_ANALYZE, 'analyze test');

# Grant select to public - this should have no affect on auditing
$strSql = 'GRANT SELECT ON TABLE public.test TO PUBLIC ';
PgLogExecute(COMMAND_GRANT, $strSql);

PgLogExecute(COMMAND_SELECT, 'select * from test');

# Now grant select to audit and it should be logged
PgAuditGrantSet($strAuditRole, &COMMAND_SELECT, 'public.test');
@oyTable = ({&NAME => 'public.test', &TYPE => &TYPE_TABLE,
			 &COMMAND => &COMMAND_SELECT});
PgLogExecute(COMMAND_SELECT, 'select * from test', \@oyTable);

# Check columns granted to public and make sure they do not log
PgAuditGrantReset($strAuditRole, &COMMAND_SELECT, 'public.test');

$strSql = 'GRANT select (name) ON TABLE public.test TO PUBLIC ';
PgLogExecute(COMMAND_GRANT, $strSql);

PgLogExecute(COMMAND_SELECT, 'select * from test');
PgLogExecute(COMMAND_SELECT, 'select from test');

# Try a select that does not reference any tables
PgLogExecute(COMMAND_SELECT, 'select 1, current_timestamp');

# Now try the same in a do block
$strSql = 'do $$ declare test int; begin select 1 into test; end $$';
PgLogExecute(COMMAND_DO, $strSql, undef, true, false);

$strSql = 'select 1';
PgLogExecute(COMMAND_SELECT, $strSql, undef, false, true);

# Insert some data into test and try a loop in a do block
PgLogExecute(COMMAND_INSERT, 'insert into test (id) values (1)');
PgLogExecute(COMMAND_INSERT, 'insert into test (id) values (2)');
PgLogExecute(COMMAND_INSERT, 'insert into test (id) values (3)');

$strSql = 'do $$ ' .
		  'declare ' .
		  '	result record;' .
		  'begin ' .
		  '	for result in select id from test loop ' .
		  '		insert into test (id) values (result.id + 100); ' .
		  '	end loop; ' .
		  'end; $$';

PgLogExecute(COMMAND_DO, $strSql, undef, true, false);

$strSql = 'select id from test';
PgLogExecute(COMMAND_SELECT, $strSql, undef, false, false);

$strSql = 'insert into test (id) values (result.id + 100)';
PgLogExecute(COMMAND_INSERT, $strSql, undef, false, false, undef, ",,");

PgLogExecute(COMMAND_INSERT, $strSql, undef, false, false, undef, ",,");

PgLogExecute(COMMAND_INSERT, $strSql, undef, false, false, undef, ",,");

# Test EXECUTE with bind
$strSql = "select * from test where id = ?";
my $hStatement = $hDb->prepare($strSql);

$strSql = "select * from test where id = \$1";
$hStatement->bind_param(1, 101);
$hStatement->execute();

PgLogExecute(COMMAND_SELECT, $strSql, undef, false, false, undef, "101");

$hStatement->bind_param(1, 103);
$hStatement->execute();

PgLogExecute(COMMAND_SELECT, $strSql, undef, false, false, undef, "103");

$hStatement->finish();

# Cursors in a function block
$strSql = "CREATE  FUNCTION public.test() RETURNS  pg_catalog.int4 LANGUAGE " .
		  "plpgsql  VOLATILE  CALLED ON NULL INPUT SECURITY INVOKER COST 100 " .
		  "  AS ' declare cur1 cursor for select * from hoge; tmp int; begin " .
		  "create table hoge (id int); open cur1; fetch cur1 into tmp; close " .
		  "cur1; return tmp; end'";

PgLogExecute(COMMAND_CREATE_FUNCTION, $strSql, 'public.test()');

$strSql = 'select public.test()';
PgLogExecute(COMMAND_SELECT, $strSql, undef, true, false);
PgLogExecute(COMMAND_EXECUTE_FUNCTION, $strSql, 'public.test', false, false);

$strSql = 'create table hoge (id int)';
PgLogExecute(COMMAND_CREATE_TABLE, $strSql, 'public.hoge', false, false);

$strSql = 'select * from hoge';
PgLogExecute(COMMAND_SELECT, $strSql, undef, false, true);
#PgLogExecute(COMMAND_SELECT, 'select public.test()');

# Now try some DDL in a do block
$strSql = 'do $$ ' .
		  'declare ' .
		  "    table_name text = 'do_table'; " . 
		  'begin ' .
		  "    execute 'create table ' || table_name || ' (\"weird name\" int)'; " .
		  "    execute 'drop table ' || table_name; " .
		  'end; $$';

PgLogExecute(COMMAND_DO, $strSql, undef, true, false);

$strSql = 'create table do_table ("weird name" int)';
PgLogExecute(COMMAND_CREATE_TABLE, $strSql, 'public.do_table', false, false);

$strSql = 'drop table do_table';
PgLogExecute(COMMAND_DROP_TABLE, $strSql, 'public.do_table', false, false);

# Generate an error in a do block and make sure the stack gets cleaned up
$strSql = 'do $$ ' .
		  'begin ' .
		  '	create table bogus.test_block (id int); ' .
		  'end; $$';

PgLogExecute(COMMAND_DO, $strSql, undef, undef, undef, undef, undef, true);
# PgLogExecute(COMMAND_SELECT, 'select 1');
# exit 0;

# Try explain
PgLogExecute(COMMAND_SELECT, 'explain select 1', undef, true, false);
PgLogExecute(COMMAND_EXPLAIN, 'explain select 1', undef, false, true);

# Now set grant to a specific column to audit and make sure it logs
# Make sure the the converse is true
PgAuditGrantSet($strAuditRole, &COMMAND_SELECT, 'public.test',
				'name, description');
PgLogExecute(COMMAND_SELECT, 'select id from test');

@oyTable = ({&NAME => 'public.test', &TYPE => &TYPE_TABLE,
			 &COMMAND => &COMMAND_SELECT});
PgLogExecute(COMMAND_SELECT, 'select name from test', \@oyTable);

# Test alter and drop table statements
$strSql = 'ALTER TABLE public.test DROP COLUMN description ';
PgLogExecute(COMMAND_ALTER_TABLE_COLUMN,
			 $strSql, 'public.test.description', true, false);
PgLogExecute(COMMAND_ALTER_TABLE,
			 $strSql, 'public.test', false, true);
@oyTable = ({&NAME => 'public.test', &TYPE => &TYPE_TABLE,
			 &COMMAND => &COMMAND_SELECT});
PgLogExecute(COMMAND_SELECT, 'select from test', \@oyTable);

$strSql = 'ALTER TABLE  public.test RENAME TO test2';
PgLogExecute(COMMAND_ALTER_TABLE, $strSql, 'public.test2');

$strSql = 'ALTER TABLE public.test2 SET SCHEMA test';
PgLogExecute(COMMAND_ALTER_TABLE, $strSql, 'test.test2');

$strSql = 'ALTER TABLE test.test2 ADD COLUMN description pg_catalog.text   ' .
		  'COLLATE pg_catalog."default"';
PgLogExecute(COMMAND_ALTER_TABLE, $strSql, 'test.test2');

$strSql = 'ALTER TABLE test.test2 DROP COLUMN description ';
PgLogExecute(COMMAND_ALTER_TABLE_COLUMN, $strSql,
			 'test.test2.description', true, false);
PgLogExecute(COMMAND_ALTER_TABLE, $strSql,
			 'test.test2', false, true);

$strSql = 'drop table test.test2';
PgLogExecute(COMMAND_DROP_TABLE, $strSql, 'test.test2', true, false);
PgLogExecute(COMMAND_DROP_TABLE_CONSTRAINT, $strSql, 'test_pkey on test.test2',
			 false, false);
PgLogExecute(COMMAND_DROP_TABLE_INDEX, $strSql, 'test.test_pkey', false, true);

$strSql = "CREATE  FUNCTION public.int_add(IN a pg_catalog.int4 , IN b " .
		  "pg_catalog.int4 ) RETURNS  pg_catalog.int4 LANGUAGE plpgsql  " .
		  "VOLATILE  CALLED ON NULL INPUT SECURITY INVOKER COST 100   AS '" .
		  " begin return a + b; end '";
PgLogExecute(COMMAND_CREATE_FUNCTION, $strSql,
			 'public.int_add(integer,integer)');
PgLogExecute(COMMAND_SELECT, "select int_add(1, 1)",
							 undef, true, false);
PgLogExecute(COMMAND_EXECUTE_FUNCTION, "select int_add(1, 1)",
									   'public.int_add', false, true);

$strSql = "CREATE AGGREGATE public.sum_test(  pg_catalog.int4) " .
		  "(SFUNC=public.int_add, STYPE=pg_catalog.int4, INITCOND='0')";
PgLogExecute(COMMAND_CREATE_AGGREGATE, $strSql, 'public.sum_test(integer)');

# There's a bug here in deparse:
$strSql = "ALTER AGGREGATE public.sum_test(integer) RENAME TO sum_test2";
PgLogExecute(COMMAND_ALTER_AGGREGATE, $strSql, 'public.sum_test2(integer)');

$strSql = "CREATE COLLATION public.collation_test (LC_COLLATE = 'de_DE', " .
		  "LC_CTYPE = 'de_DE')";
PgLogExecute(COMMAND_CREATE_COLLATION, $strSql, 'public.collation_test');

$strSql =  "ALTER COLLATION public.collation_test RENAME TO collation_test2";
PgLogExecute(COMMAND_ALTER_COLLATION, $strSql, 'public.collation_test2');

$strSql = "CREATE  CONVERSION public.conversion_test FOR 'SQL_ASCII' " .
		  "TO 'MULE_INTERNAL' FROM pg_catalog.ascii_to_mic";
PgLogExecute(COMMAND_CREATE_CONVERSION, $strSql, 'public.conversion_test');

$strSql = "ALTER CONVERSION public.conversion_test RENAME TO conversion_test2";
PgLogExecute(COMMAND_ALTER_CONVERSION, $strSql, 'public.conversion_test2');

PgLogExecute(COMMAND_CREATE_DATABASE, "CREATE DATABASE database_test");
PgLogExecute(COMMAND_ALTER_DATABASE,
			 "ALTER DATABASE database_test rename to database_test2");
PgLogExecute(COMMAND_DROP_DATABASE, "DROP DATABASE database_test2");

# Make sure there are no more audit events pending in the postgres log
PgLogWait();

# Stop the database
if (!$bNoCleanup)
{
	PgDrop();
}
