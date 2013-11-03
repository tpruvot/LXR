#!/usr/bin/perl
# -*- tab-width: 4 -*-"
###############################################
#
# $Id: recreatedb.pl,v 1.4 2012/09/29 20:30:46 ajlittoz Exp $
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#
###############################################

# $Id: recreatedb.pl,v 1.4 2012/09/29 20:30:46 ajlittoz Exp $

use strict;
use lib 'lib', 'scripts';
use Fcntl;
use Getopt::Long;
use IO::Handle;
use File::MMagic;
use File::Path qw(make_path);

use LXR::Files;
use LXR::Index;
use LXR::Common;

use ExpandSlashStar;
use QuestionAnswer;
use VTescape;


##############################################################
#
#				Global definitions
#
##############################################################

#	This is a nasty trick to fool Perl into accepting the CVS
#	revision tag without trying to make sense with a supposed
#	variable (sigils may be separated from the variable name
#	by spaces! Not documented of course!)
$_ = '';	# Calm down Perl ardour
my $version ="\$Revision: 1.4 $_";
$version =~ s/Revision: (.*) $/$1/;
$version =~ s/\$//;

#	Who am I? Strip directory path.
my $cmdname = $0;
$cmdname =~ s:.*/([^/]+)$:$1:;

#	Default record separator
#	changed to read full file content at once and restored afterwards
my $oldsep = $/;


##############################################################
#
#			Parse options and check environment
#
##############################################################

# Define default values for options and process command line
my %option;
my $confdir = 'custom.d';
my $rootdir = `pwd`;
chomp($rootdir);
my $tmpldir = 'templates';
my $verbose;
my $scriptout = 'initdb.sh';
my $lxrconf = 'lxr.conf';
my $lxrctxdft = 'lxr.ctxt';
my $lxrctx;
if (!GetOptions	(\%option
				, 'conf-dir=s'	=> \$confdir
				, 'help|h|?'
				, 'lxr-ctx=s'	=> \$lxrctx
				, 'root-dir=s'	=> \$rootdir
				, 'script-out=s'=> \$scriptout
				, 'tmpl-dir=s'	=> \$tmpldir
				, 'verbose|v'	=> \$verbose
				, 'version'
				)
	) {
	exit 1;
}

if ($option{'help'}) {
	print <<END_HELP;
Usage:  ${cmdname} [option ...] [lxr-conf-file]

Reconstructs the DB initialisation script from 'lxr.conf' content
as it was initially created by configure-lxr.pl program.

Valid options are:
      --conf-dir=directory
                  Define user-configuration directory
                  (default: $confdir)
  -h, --help      Print this summary and quit
      --lxr-ctx=filename
                  Initial configuration context file
                  (default: $lxrctxdft, i.e. same name as
                  lxr-conf-file with extension replaced by
                  ".ctxt")
      --root-dir=directory
                  LXR root directory name
                  (default: $rootdir, i.e. the directory
                  from which you run this script)
      --script-out=filename (without directory component)
                  Define custom DB initialisation script name
                  (default: $scriptout)
      --tmpl-dir=directory
                  Define template directory
                  (default: $tmpldir)
  -v, --verbose   Explain what is being done
      --version   Print version information and quit

lxr-conf-file  LXR master configuration file from which the
               DB initialisation script will be reconstructed
               (defaults to $lxrconf if not specified)  

LXR home page: <http://lxr.sourceforge.net>
Report bugs at http://sourceforge.net/projects/lxr/.
END_HELP
	exit 0;
}

if ($option{'version'}) {
	print <<END_VERSION;
${cmdname} version $version
(C) 2012 A. J. Littoz
This is free software under GPL v3 (or higher) licence.
There is NO warranty, not even for MERCHANTABILITY nor
FITNESS FOR A PARICULAR PURPOSE to the extent permitted by law.

LXR home page: <http://lxr.sourceforge.net>
See home page for bug reports.
END_VERSION
	exit 0;
}

#	"Canonise" directory names
$confdir =~ s:/*$::;
$tmpldir =~ s:/*$::;
$rootdir =~ s:/*$::;

#	Check LXR environment
my $error = 0;
if (! -d $rootdir) {
	print "${VTred}ERROR:${VTnorm} directory"
		. " ${VTred}$rootdir${VTnorm} does not exist!\n";
	$error = 1;
}
if (! -d $rootdir.'/scripts') {
	print "${VTred}ERROR:${VTnorm} ${VTred}$rootdir${VTnorm} does not look "
		. "like an LXR root directory (scripts directory not found)!\n";
	$error = 1;
}
if (! -d $tmpldir) {
	print "${VTred}ERROR:${VTnorm} directory"
		. " ${VTred}$tmpldir${VTnorm} does not exist!\n";
	$error = 1;
}

if ($scriptout =~ m:/:) {
	print "${VTred}ERROR:${VTnorm} output script ${VTred}$scriptout${VTnorm} should not contain directory name!\n";
	$error = 1;
}

if (@ARGV > 1) {
	print "${VTred}ERROR:${VTnorm} only one configuration file can be given!\n";
	$error = 1;
}
if (@ARGV == 1) {
	$lxrconf = $ARGV[0];
}

# If lxr-ctx not given, use default companion filename
if (! $lxrctx) {
	$lxrctx		= $lxrconf;
	$lxrctx		=~ s/\.[^.]*$//;	# Remove extension
	$lxrctxdft	=~ s/^[^.]*//;	# Context file extension
	$lxrctx		=~ s/$/$lxrctxdft/;	# Insert correct extension
	if ($lxrctx !~ m!/!) {
		$lxrctx = $confdir . '/' . $lxrctx;
	}
}
if (! -e "$lxrctx") {
	print "${VTred}ERROR:${VTnorm} configuration context file"
		. " ${VTred}$lxrctx${VTnorm} does not exist!\n";
}

if (! -e "$tmpldir/initdb/initdb-m-template.sql") {
	print "${VTred}ERROR:${VTnorm} template file"
		. " ${VTred}$tmpldir/initdb/initdb-m-template.sql{VTnorm} does not exist!\n";
	$error = 1;
}
if (! -e "$tmpldir/initdb/initdb-o-template.sql") {
	print "${VTred}ERROR:${VTnorm} template file"
		. " ${VTred}$tmpldir/initdb/initdb-o-template.sql{VTnorm} does not exist!\n";
	$error = 1;
}
if (! -e "$tmpldir/initdb/initdb-p-template.sql") {
	print "${VTred}ERROR:${VTnorm} template file"
		. " ${VTred}$tmpldir/initdb/initdb-p-template.sql{VTnorm} does not exist!\n";
	$error = 1;
}
if (! -e "$tmpldir/initdb/initdb-s-template.sql") {
	print "${VTred}ERROR:${VTnorm} template file"
		. " ${VTred}$tmpldir/initdb/initdb-s-template.sql{VTnorm} does not exist!\n";
	$error = 1;
}

exit $error if $error;


##############################################################
#
#				Start recontruction
#
##############################################################

if ($verbose) {
	print "${VTyellow}***${VTnorm} ${VTred}L${VTblue}X${VTgreen}R${VTnorm} DB initialisation reconstruction  (version: $version) ${VTyellow}***${VTnorm}\n";
	print "\n";
	print "LXR root directory is ${VTbold}$rootdir${VTnorm}\n";
	print "Configuration read from ${VTbold}$lxrconf${VTnorm}\n";
}

if (! -d $confdir) {
	make_path($confdir);	# equivalent to mkdir -p
	if ($verbose) {
		print "directory ${VTbold}$confdir${VTnorm} created\n";
	}
}

##############################################################
#
#				Define global parameters
#
##############################################################

if ($verbose) {
	print "\n";
}

my $cardinality;
my $dbengine;
my $dbenginechanged = 1;
my $dbpolicy;
my $dbname;
my $dbuser;
my $dbpass;
my $dbprefix;
my $nodbuser;
my $nodbprefix;
my %users;			# Cumulative list of all user/password
# Flags for first use of DB engine
my %dbengine_seen =
	( 'm' => 0
	, 'o' => 0
	, 'p' => 0
	, 's' => 0	# Silly, but does not break scheme
	);


##############################################################
#
#			Reload context from initial configuration
#
##############################################################

# WARNING:	remember to keep this number in sync with
#			configure-lxr.pl.
my $context_version = 1;
my $manualreload = 0;

if (my $c=open(SOURCE, '<', $lxrctx)) {
	print "Initial context $lxrctx is reloaded\n" if $verbose;
	$/ = undef;
	my $context = <SOURCE>;
	$/ = $oldsep;
	close(SOURCE);
	my $context_created;
	eval($context);
	if (!defined($context_created)) {
		print "${VTred}ERROR:${VTnorm} saved context file probably damaged!\n";
		print "Check variable not found\n";
		print "Delete or rename file $lxrctx to remove lock.\n";
		exit 1;
	}
	if ($context_created != $context_version) {
		print "${VTred}ERROR:${VTnorm} saved context file probably too old!\n";
		print "Recorded state version = $context_created while expecting version = $context_version\n";
		print "It is wise to 'quit' now and add manually the new tree or reconfigure from scratch.\n";
		print "You can however try to restore the initial context at your own risk.\n";
		print "\n";
		print "${VTyellow}WARNING:${VTnorm} inconsistent answers can lead to LXR malfunction.\n";
		print "\n";
		if ('q' eq get_user_choice
			( 'Do you want to quit or manually restore context?'
			, 1
			, [ 'quit', 'restore' ]
			, [ 'q', 'r' ]
			) ) {
			exit 1;
		}
		$manualreload = 1;
	};
	if ($dbpolicy eq 't') {
		print "Your DB engine was: ${VTbold}" if $verbose;
		if ("m" eq $dbengine) {
			print "MySQL\n" if $verbose;
		} elsif ("o" eq $dbengine) {
			print "Oracle\n" if $verbose;
		} elsif ("p" eq $dbengine) {
			print "PostgreSQL\n" if $verbose;
		} elsif ("s" eq $dbengine) {
			print "SQLite\n" if $verbose;
		} else {
			print "???${VTnorm}\n" if $verbose;
			print "${VTred}ERROR:${VTnorm} saved context file damaged or tampered with!\n";
			print "Unknown database code '$dbengine'\n";
			print "Delete or rename file $lxrctx to remove lock.\n";
			if ('q' eq get_user_choice
				( 'Do you want to quit or manually restore context?'
				, 1
				, [ 'quit', 'restore' ]
				, [ 'q', 'r' ]
				) ) {
				exit 1;
			}
			$manualreload = 1;
		};
	}
} else {
	print "${VTyellow}WARNING:${VTnorm} could not reload context file ${VTbold}$lxrctx${VTnorm}!\n";
	print "You may have deleted the context file or you moved the configuration\n";
	print "file out of the ${VTbold}${confdir}${VTnorm} user-configuration directory without the\n";
	print "context companion file ${VTyellow}$lxrctx${VTnorm}.\n";
	print "\n";
	print "You can now 'quit' to think about the situation or try to restore\n";
	print "the parameters by answering the following questions\n";
	print "(some clues can be gathered from reading configuration file ${VTbold}$lxrconf${VTnorm}).\n";
	print "\n";
	print "${VTyellow}WARNING:${VTnorm} inconsistent answers can lead to LXR malfunction.\n";
	print "\n";
	if ('q' eq get_user_choice
		( 'Do you want to quit or manually restore context?'
		, 1
		, [ 'quit', 'restore' ]
		, [ 'q', 'r' ]
		) ) {
		exit 1;
	};
	$manualreload = 1;
}

if ($manualreload) {
	print "\n";
	if ($verbose) {
		print "The following questions are intended to rebuild the global\n";
		print "databases options (which may be overridden in individual\n";
		print "trees. Answer with the choices you made previously,\n";
		print "otherwise your DB will not be what LXR expects.\n";
	}
	$dbengine =  get_user_choice
			( 'Default database engine?'
			, 1
			, [ 'mysql', 'oracle', 'postgres', 'sqlite' ]
			, [ 'm', 'o', 'p', 's' ]
			);

	#	Are we configuring for single tree or multiple trees?
	$cardinality = get_user_choice
			( 'Configured for single/multiple trees?'
			, 2
			, [ 's', 'm' ]
			, [ 's', 'm' ]
			);

	if ($cardinality eq 's') { 
		if ('y' eq get_user_choice
				( 'Do you intend to add other trees later?'
				, 2
				, [ 'yes', 'no' ]
				, [ 'y', 'n']
				)
			) {
			$cardinality = 'm';
			print "${VTyellow}NOTE:${VTnorm} installation switched to ${VTbold}multiple${VTnorm} mode\n";
			print "      but describe just a single tree.\n";
		} else {
			$dbpolicy   = 't';
			$nodbuser   = 1;
			$nodbprefix = 1;
		}
	}

	if ($cardinality eq 'm') {
		if ('o' ne $dbengine) {
			print "The safest option is to create one database per tree.\n";
			print "You can however create a single database for all your trees with a specific set of\n";
			print "tables for each tree (though this is not recommended).\n";
			$dbpolicy = get_user_choice
					( 'How did you setup the databases?'
					, 1
					, [ 'per tree', 'global' ]
					, [ 't', 'g' ]
					);
			if ($dbpolicy eq 'g') {	# Single global database
				if ('s' eq $dbengine) {
					$dbname = get_user_choice
						( 'Name of global SQLite database file? (e.g. /home/myself/SQL-databases/lxr'
						, -2
						, []
						, []
						);
				} else {
					$dbname = get_user_choice
						( 'Name of global database?'
						, -1
						, []
						, [ 'lxr' ]
						);
				}
				$nodbprefix = 1;
			}
		} else {
			print "There is only one global database under Oracle.\n";
			print "The tables for each tree are identified by a unique prefix.\n";
			$dbpolicy   = 'g';
			$nodbprefix = 1;
		}
		print "All databases can be accessed with the same username and\n";
		print "can also be described under the same names.\n";
		if ('n' eq get_user_choice
				( 'Have you shared database characteristics?'
				, 1
				, [ 'yes', 'no' ]
				, [ 'y', 'n']
				)
			) {
			$nodbuser   = 1;
			$nodbprefix = 1;
		}
	}

	if (!defined($nodbuser)) {
		if	(  $dbpolicy eq 'g'
			|| 'y' eq get_user_choice
				( 'Did you use the same username and password for all DBs?'
				, 1
				, [ 'yes', 'no' ]
				, [ 'y', 'n']
				)
			) {
			$dbuser = get_user_choice
				( '--- DB user name?'
				, -1
				, []
				, [ 'lxr' ]
				);
			$dbpass = get_user_choice
				( '--- DB password ?'
				, -1
				, []
				, [ 'lxrpw' ]
				);
			$users{$dbuser} = $dbpass;	# Record global user/password
		} else {
			$nodbuser = 1;
		}
	}

	if (!defined($nodbprefix)) {
		if ('y' eq get_user_choice
				( 'Did you give the same prefix to all tables?'
				, 1
				, [ 'yes', 'no' ]
				, [ 'y', 'n']
				)
			) {
			$dbprefix = get_user_choice
					( '--- Common table prefix?'
					, -1
					, []
					, [ 'lxr_' ]
					);
		}else {
			$nodbprefix = 1;
		}
	}
}

##############################################################
#
#					Read lxr.conf
#
##############################################################

# Dummy sub to disable 'range' file reads
sub readfile {}

unless (open(CONFIG, $lxrconf)) {
	print "${VTred}ERROR:${VTnorm} could not open configuration file ${VTred}$lxrconf${VTnorm}\n";
	exit(1);
}
$/ = undef;
my $config_contents = <CONFIG>;
$/ = $oldsep;
close(CONFIG);
$config_contents =~ /(.*)/s;
$config_contents = $1;    #untaint it
my @config = eval("\n#line 1 \"configuration file\"\n" . $config_contents);
die($@) if $@;

print "Configuration file $lxrconf loaded\n" if $verbose;


##############################################################
#
#			Scan lxr.conf's global part
#			and build database description
#
##############################################################

if ($verbose) {
	print "\n";
	print "${VTyellow}***${VTnorm} scanning global configuration section ${VTyellow}***${VTnorm}\n";
}
if (exists($config[0]{'dbuser'})) {
	$dbuser = $config[0]{'dbuser'};
	$dbpass = $config[0]{'dbpass'};
}
if (exists($config[0]{'dbprefix'})) {
	$dbprefix = $config[0]{'dbprefix'};
}
if (exists($config->{'dbname'})) {
	$config->{'dbname'} =~ m/dbi:(.)/;
	$dbengine = lc($1);
	if ($config->{'dbname'} =~ m/dbname=([^;]+)/) {
		$dbname = $1;
	}
}
shift @config;	# Remove global part

##############################################################
#
#			Set variables needed by the expanders
#
##############################################################

my %option_trans =
		( 'context' => $cardinality
		, 'dbpass'	=> $dbpass
		, 'dbpolicy'=> $dbpolicy
		, 'dbprefix'=> $dbprefix
		, 'dbuser'	=> $dbuser
		, 'dbuseroverride' => 0
		, 'nodbuser'=> $nodbuser
		, 'nodbprefix' => $nodbprefix
		);


my %markers;
my $sample;
$markers{'%LXRroot%'} = $rootdir;

$markers{'%DB_name%'} = $dbname if $dbname;
$markers{'%DB_user%'} = $dbuser if $dbuser;
$markers{'%DB_password%'} = $dbpass if $dbpass;
$markers{'%DB_global_prefix%'} = $dbprefix if $dbprefix;


##############################################################
#
#			Scan lxr.conf's tree-specific parts
#			and build database description
#
##############################################################

unlink "${confdir}/${scriptout}";
open(DEST, '>>', "${confdir}/${scriptout}")
or die("${VTred}ERROR:${VTnorm} couldn't open output file \"${confdir}/$scriptout\"\n");

if ($verbose) {
	print "\n";
}
foreach my $config (@config) {

	if ($verbose) {
		print "${VTyellow}***${VTnorm} scanning ${VTbold}$$config{'virtroot'}${VTnorm} tree configuration section ${VTyellow}***${VTnorm}\n";
	}
	#	Start each iteration in default configuration
	$option_trans{'dbuseroverride'} = 0;
	delete $markers{'%DB_tree_user%'};
	delete $markers{'%DB_tree_password'};
	delete $markers{'%DB_tbl_prefix%'};

	#	Have new DB user and password been defined?
	if (exists($config->{'dbuser'})) {
		$option_trans{'dbuseroverride'} = 1;
		$users{$markers{'%DB_tree_user%'}} = $config->{'dbuser'};
	}
	if (exists($config->{'dbpass'})) {
		$option_trans{'dbuseroverride'} = 1;
		$users{$markers{'%DB_tree_password%'}} = $config->{'dbpass'};
	}
	#	New DB table prefix?
	if (!exists($config->{'dbprefix'})) {
		$markers{'%DB_tbl_prefix%'} = $config->{'dbprefix'};
	}
	if (!defined($config->{'dbprefix'})) {
		$markers{'%DB_tbl_prefix%'} = $dbprefix;
	}

	my $treedbengine = $dbengine;
	if (exists($config->{'dbname'})) {
		$config->{'dbname'} =~ m/dbi:(.)/;
		$treedbengine = lc($1);
		if ($config->{'dbname'} =~ m/dbname=([^;]+)/) {
			$markers{'%DB_name%'} = $1;
		}
	}
	if (!defined($markers{'%DB_name%'})) {
		$markers{'%DB_name%'} = $dbname;
	}
	if (!defined($markers{'%DB_name%'})) {
		print "${VTred}ERROR:${VTnorm} no data base name (either tree-specific or global)\n";
		print "for tree ${VTred}$$config{'virtroot'}${VTnorm}!\n";
	}

	$option_trans{'createglobals'} =
		$dbenginechanged
		|| $treedbengine ne $dbengine && !$dbengine_seen{$treedbengine};
	$dbengine_seen{$treedbengine} = 1;

	open(SOURCE, '<', "${tmpldir}/initdb/initdb-${treedbengine}-template.sql")
	or die("${VTred}ERROR:${VTnorm} couldn't open  script template file \"${tmpldir}/initdb/initdb-${dbengine}-template.sql\"\n");

	# NOTE:
	#	The design of the configuration process left the possibility
	#	to expand the SQL templates without interspersing the results
	#	with shell commands (so that the result would be a sequence
	#	of SQL commands only).
	#	Initially, the sub expand_slash_star was intended to be a script
	#	to which others would connect through a pipe.
	#	A shell expander would pass --shell to expand_slash_star to enable
	#	shell commands, while an SQL expander script would not pass
	#	this option.
	#	This is why the 'shell' pseudo-option is created.
	#	Of course, this statement would be better outside the loop,
	#	but this comment would be far from expand_slash_star invocation.
	$option_trans{'shell'} = 1;
	#	Expand script model
	expand_slash_star	( \*SOURCE
				, \*DEST
				, '~~~TO~EOF~~~'	# Hope this is never used as a label!
				, \%markers
				, \%option_trans
				, $verbose
				);

	close(SOURCE);

	#	Prevent doing one-time actions more than once
	$option_trans{'createglobals'} = 0;
	$dbenginechanged = 0;
}

close(DEST);
chmod 0775,"${confdir}/${scriptout}";	# Make sure script has x permission
