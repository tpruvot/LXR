#!/usr/bin/perl
# -*- tab-width: 4 -*-
###############################################
#
# $Id: configure-lxr.pl,v 1.5 2012/09/30 07:27:06 ajlittoz Exp $
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

# $Id: configure-lxr.pl,v 1.5 2012/09/30 07:27:06 ajlittoz Exp $

use strict;
use Getopt::Long qw(:config gnu_getopt);
use File::Path qw(make_path);
use lib do { $0 =~ m{(.*)/}; "$1" };
use ExpandHash;
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
my $version ="\$Revision: 1.5 $_";
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
my $addtree = 0;
my $confdir = 'custom.d';
my $rootdir = `pwd`;
chomp($rootdir);
my $tmpldir = 'templates';
my $verbose;
my $confout;
my $scriptout = 'initdb.sh';
my $lxrtmplconf = 'lxr.conf';
if (!GetOptions	(\%option
				, 'add|a'		=> \$addtree
				, 'conf-dir=s'	=> \$confdir
				, 'conf-out=s'	=> \$confout
				, 'help|h|?'
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
Usage: ${cmdname} [option ...] [lxr-conf-template]

Creates in confdir all configuration files and scripts needed to run LXR.

Valid options are:
  -a, --add       Add a new tree to an existing configuration
      --conf-dir=directory
                  Define user-configuration directory
                  (default: $confdir)
      --conf-out=filename (without directory component)
                  Define custom configuration output filename
                  (default: same name as lxr-conf-template)
  -h, --help      Print this summary and quit
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

lxr-conf-template  LXR master configuration template name in templates/
                   sub-directory (defaults to $lxrtmplconf if not specified)  

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
	print "${VTred}ERROR:${VTnorm} only one template can be given!\n";
	$error = 1;
}
if (@ARGV == 1) {
	$lxrtmplconf = $ARGV[0];
	if ($lxrtmplconf =~ m:/:) {
		print "${VTred}ERROR:${VTnorm} template ${VTred}$lxrtmplconf${VTnorm} should not contain directory name!\n";
	$error = 1;
	}
}
if (! -e "$tmpldir/$lxrtmplconf") {
	print "${VTred}ERROR:${VTnorm} template file"
		. " ${VTred}$tmpldir/$lxrtmplconf${VTnorm} does not exist!\n";
	$error = 1;
}

$confout =  $lxrtmplconf unless defined($confout);
if ($confout =~ m:/:) {
	print "${VTred}ERROR:${VTnorm} output configuration ${VTred}$confout${VTnorm} should not contain directory name!\n";
	$error = 1;
}
if ($confout =~ m:\.ctxt$:) {
	print "${VTred}ERROR:${VTnorm} output configuration file ${VTred}$confout${VTnorm} has a forbidden extension!\n";
	$error = 1;
}
if ($confout !~ m:\.conf$:) {
	print "${VTyellow}WARNING:${VTnorm} output configuration file ${VTbold}$confout${VTnorm} has an unusual extension!\n";
}

exit $error if $error;

my $contextfile = $confout // $lxrtmplconf;
$contextfile =~ s!(?:\.[^/]*|)$!.ctxt!;


##############################################################
#
#				Start configuration
#
##############################################################

if ($verbose) {
	print "${VTyellow}***${VTnorm} ${VTred}L${VTblue}X${VTgreen}R${VTnorm} configurator (version: $version) ${VTyellow}***${VTnorm}\n";
	print "\n";
	print "LXR root directory is ${VTbold}$rootdir${VTnorm}\n";
	print "Configuration will be stored in ${VTbold}$confdir/${VTnorm}\n";
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
my $dbenginechanged = 0;
my $dbpolicy;
my $dbname;
my $dbuser;
my $dbpass;
my $dbprefix;
my $nodbuser;
my $nodbprefix;
my %users;			# Cumulative list of all user/password

# WARNING:	remember to increment this number when changing the
#			set of state variables and/or their meaning.
my $context_version = 1;

if ($addtree) {
	if ($verbose) {
		print "== ${VTyellow}ADD MODE${VTnorm} ==\n";
		print "\n";
	}
	if (my $c=open(SOURCE, '<', "$confdir/$contextfile")) {
		print "Initial context $confdir/$contextfile is reloaded\n" if $verbose;
		$/ = undef;
		my $context = <SOURCE>;
		$/ = $oldsep;
		close(SOURCE);
		my $context_created;
		eval($context);
		if (!defined($context_created)) {
			print "${VTred}ERROR:${VTnorm} saved context file probably damaged!\n";
			print "Check variable not found\n";
			print "Delete or rename file $confdir/$contextfile to remove lock.\n";
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
			$addtree = 2;
		};
		if ($cardinality eq 's') {
			print "${VTred}ERROR:${VTnorm} initial configuration was done for a single tree!\n";
			print "This is not compatible with the present web server configuration.\n";
			print "To add more trees, you must reconfigure for multiple trees.\n";
			exit 1;
		}
		if ($dbpolicy eq 't') {
			print "Your DB engine was: ${VTbold}";
			if ("m" eq $dbengine) {
				print "MySQL";
			} elsif ("o" eq $dbengine) {
				print "Oracle";
			} elsif ("p" eq $dbengine) {
				print "PostgreSQL";
			} elsif ("s" eq $dbengine) {
				print "SQLite";
			} else {
				print "???${VTnorm}\n";
				print "${VTred}ERROR:${VTnorm} saved context file damaged or tampered with!\n";
				print "Unknown database code '$dbengine'\n";
				print "Delete or rename file $confdir/$contextfile to remove lock.\n";
				if ('q' eq get_user_choice
					( 'Do you want to quit or manually restore context?'
					, 1
					, [ 'quit', 'restore' ]
					, [ 'q', 'r' ]
					) ) {
					exit 1;
				}
				$addtree = 2;
			};
			print "${VTnorm}\n";
			print "Advanced users can configure different DB engines for different trees.\n";
			print "This is not recommended for average users.\n";
			if ('n' eq get_user_choice
					( 'Use previous DB engine?'
					, 1
					, [ 'yes', 'no' ]
					, [ 'y', 'n' ]
					) ) {
				$dbengine =  get_user_choice
						( 'New database engine?'
						, 3
						, [ 'mysql', 'oracle', 'postgres', 'sqlite' ]
						, [ 'm', 'o', 'p', 's' ]
						);
				$dbenginechanged = 1;
			}
		}
	} else {
		print "${VTyellow}WARNING:${VTnorm} could not reload context file ${VTbold}$confout${VTnorm}!\n";
		print "You may have deleted the context file or you moved the configuration\n";
		print "file out of the ${VTbold}${confdir}${VTnorm} user-configuration directory without the\n";
		print "context companion file ${VTyellow}$contextfile${VTnorm}.\n";
		print "\n";
		print "You can now 'quit' to think about the situation or try to restore\n";
		print "the parameters by answering the following questions\n";
		print "(some clues can be gathered from reading configuration file ${VTbold}$confout${VTnorm}).\n";
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
		$addtree = 2;
	}
}

if ($addtree != 1) {
	if ($verbose) {
		print "The choice of the database engine can make a difference in indexing performance,\n";
		print "but resource consumption is also an important factor.\n";
		print "  * For a small personal project, try ${VTbold}SQLite${VTnorm} which do not\n";
		print "    need a server and is free from configuration burden.\n";
		print "  * For medium to large projects, choice is between ${VTbold}MySQL${VTnorm},\n";
		print "    ${VTbold}PostgreSQL${VTnorm} and Oracle.\n";
		print "    Oracle is not a free software, its interface has not been\n";
		print "    tested for a long time.\n";
		print "  * ${VTbold}PostgreSQL${VTnorm} databases are smaller than MySQL's\n";
		print "    and performance is roughly equivalent.\n";
		print "  * ${VTbold}MySQL${VTnorm} is at its best with large-sized projects\n";
		print "    (such as kernel cross-referencing) where it is fastest at the cost\n";
		print "    of bigger databases.\n";
		print "  * Take also in consideration the number of connected users.\n";
	}
	$dbengine =  get_user_choice
			( 'Database engine?'
			, 1
			, [ 'mysql', 'oracle', 'postgres', 'sqlite' ]
			, [ 'm', 'o', 'p', 's' ]
			);

	#	Are we configuring for single tree or multiple trees?
	$cardinality = get_user_choice
			( 'Configure for single/multiple trees?'
			, 1
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
					( 'How do you setup the databases?'
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
				( 'Will you share database characteristics?'
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
				( 'Will you use the same username and password for all DBs?'
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
				( 'Will you give the same prefix to all tables?'
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
#			Save context for future additions
#
##############################################################

if (!$addtree) {
	if (open(DEST, '>', "$confdir/$contextfile")) {
		print DEST "# -*- mode: perl -*-\n";
		print DEST "# Context file associated with $confout\n";
		my @t = gmtime(time());
		my ($sec, $min, $hour, $mday, $mon, $year) = @t;
		my $date_time = sprintf	( "%04d-%02d-%02d %02d:%02d:%02d"
								, $year + 1900, $mon + 1, $mday
								, $hour, $min, $sec
								);
		print DEST "# Created $date_time UTC\n";
		print DEST "# Strictly internal, do not play with content\n";
		print DEST "\$context_created = $context_version;\n";
		print DEST "\n";
		print DEST "\$cardinality = '$cardinality';\n";
		print DEST "\$dbpolicy = '$dbpolicy';\n";
		print DEST "\$dbengine = '$dbengine';\n";
		if ("g" eq $dbpolicy) {
			print DEST "\$dbname = '$dbname';\n";
		}
		if ($nodbuser) {
			print DEST "\$nodbuser = 1;\n";
		} else {
			print DEST "\$dbuser = '$dbuser';\n";
			print DEST "\$dbpass = '$dbpass';\n";
		}
		if ($nodbprefix) {
			print DEST "\$nodbprefix = 1;\n";
		} else {
			print DEST "\$dbprefix = '$dbprefix'\n";
		}
		close(DEST)
		or print "${VTyellow}WARNING:${VTnorm} error $! when closing context file ${VTbold}$confout${VTnorm}!\n";
	} else {
		print "${VTyellow}WARNING:${VTnorm} could not create context file ${VTbold}$confout${VTnorm}, autoreload disabled!\n";
	}
}

##############################################################
#
#			Set variables needed by the expanders
#
##############################################################

my %option_trans =
		( 'add'		=> $addtree
		, 'context' => $cardinality
		, 'createglobals' => $cardinality eq 'm'
							&&	(  0 == $addtree
								|| 1 == $dbenginechanged
								)
		, 'dbengine'=> $dbengine
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
$sample = `command -v glimpse 2>/dev/null`;
chomp($sample);
$markers{'%glimpse%'} = $sample if $sample;
$sample = `command -v glimpseindex 2>/dev/null`;
chomp($sample);
$markers{'%glimpseindex%'} = $sample if $sample;
$sample = `command -v swish-e 2>/dev/null`;
chomp($sample);
$markers{'%swish%'} = $sample if $sample;
$sample = `command -v ctags 2>/dev/null`;
chomp($sample);
$markers{'%ctags%'} = $sample if $sample;

$markers{'%DB_name%'} = $dbname if $dbname;
$markers{'%DB_user%'} = $dbuser if $dbuser;
$markers{'%DB_password%'} = $dbpass if $dbpass;
$markers{'%DB_global_prefix%'} = $dbprefix if $dbprefix;

$markers{'%search_engine%'} = 'glimpse';	# glimpse will have priority
if (!$addtree) {
	if	(  !defined($markers{'%glimpse%'})
		&& !defined($markers{'%swish%'})
		) {
		print "${VTred}ERROR:${VTnorm} neither glimpse nor swish-e found in \$PATH!\n";
		if ('y' eq get_user_choice
				( 'Is your source tree stored in a VCS repository?'
				, 2
				, [ 'yes', 'no' ]
				, [ 'y', 'n']
				)
			) {
			print "Since free-text search is not compatible with VCSes, you can continue\n";
			$markers{'%glimpse%'} = '/bin/true';	# disable free-text search
		} elsif ('y' eq get_user_choice
				( 'Does one of them exist in a non standard directory?'
				, 1
				, [ 'yes', 'no' ]
				, [ 'y', 'n']
				)
			) {
			my $search = get_user_choice
					( '--- Which is it?'
					, 1
					, [ 'glimpse',   'swish-e' ]
					, [ '%glimpse%', '%swish%' ]
					);
			if ($search eq '%glimpse%') {
				$markers{'%glimpse%'} = get_user_choice
					( "--- Location? (e.g. /usr/share/glimpse-dir/glimpse)"
					, -2
					, []
					, []
					);
				$markers{'%glimpseindex%'} = get_user_choice
					( '--- Location of indexer? (e.g. /usr/share/glimpse-dir/glimpseindex)'
					, -2
					, []
					, []
					);
			} else {
				$markers{'%swish%'} = get_user_choice
					( "--- Location? (e.g. /usr/share/swish-dir/swish-e)"
					, -2
					, []
					, []
					);
			}
		} else {
			print "${VTyellow}Sorry:${VTnorm} free-text search disabled\n";
			$markers{'%glimpse%'} = '/bin/true';	# disable free-text search
		}
	}

	if	(  defined($markers{'%glimpse%'})
		&& $markers{'%glimpse%'} ne '/bin/true'
		) {
		$markers{'%glimpsedirbase%'} = get_user_choice
					( '--- Directory for glimpse databases?'
					, -2
					, []
					, []
					);
	}
	if (defined($markers{'%swish%'})) {
		$markers{'%swishdirbase%'} = get_user_choice
					( '--- Directory for swish-e databases?'
					, -2
					, []
					, []
					);
		if	(  !defined($markers{'%glimpse%'})
			|| $markers{'%glimpse%'} eq '/bin/true'
			) {
			$markers{'%search_engine%'} = 'swish';
		}
	}
	if	(  defined($markers{'%glimpse%'})
		&& $markers{'%glimpse%'} ne '/bin/true'
		&& defined($markers{'%swish%'})
		) {
		print "${VTred}REMINDER:${VTyellow} after this configuration step, open ${VTnorm}${VTbold}$confout${VTnorm}${VTyellow}\n";
		print "and comment out one of 'glimpsebin' or 'swishbin'.${VTnorm}\n";
	}
}

##############################################################
#
#			Copy basic files from templates directory
#
##############################################################

if (!$addtree) {
	print "\n" if $verbose;

	chmod(0555, $tmpldir);
	if ($verbose) {
		print "templates directory ${VTbold}$tmpldir/${VTnorm} now protected read-only\n"
	}

	my $target;
	my $target_contents;

	#	Apache: per-directory access control file
	$target = '.htaccess';
	`cp ${tmpldir}/Apache/htaccess-generic ${rootdir}/$target`;
	chmod(0775, "${rootdir}/$target");
	if ($verbose) {
		print "file ${VTbold}$target${VTnorm} written into LXR root directory\n"
	}

	#	Apache: mod_perl startup file
	$target = 'apache2-require.pl';
	unless (open(SOURCE, '<', "${tmpldir}/Apache/$target")) {
		die("${VTred}ERROR:${VTnorm} couldn't open template file \"${tmpldir}/Apache/$target\"\n");
	}
	$/ = undef;
	$target_contents = <SOURCE>;
	$/ = $oldsep;
	close(SOURCE);
	$target_contents =~ s/%LXRroot%/$rootdir/g;
	unless (open(DEST, '>', "${confdir}/${target}")) {
		die("${VTred}ERROR:${VTnorm} couldn't open output file \"${confdir}/$target\n");
	}
	print DEST $target_contents;
	close(DEST);
	if ($verbose) {
		print "file ${VTbold}$target${VTnorm} written into configuration directory\n"
	}

	#	Apache: LXR server configuration file
	$target = 'apache-lxrserver.conf';
	unless (open(SOURCE, '<', "${tmpldir}/Apache/$target")) {
		die("${VTred}ERROR:${VTnorm} couldn't open template file \"${tmpldir}/Apache/$target\"\n");
	}
	$/ = undef;
	$target_contents = <SOURCE>;
	$/ = $oldsep;
	close(SOURCE);
	$target_contents =~ s/%LXRroot%/$rootdir/g;
	$target_contents =~ s/#=$cardinality=//g;
	unless (open(DEST, '>', "${confdir}/${target}")) {
		die("${VTred}ERROR:${VTnorm} couldn't open output file \"${confdir}/$target\n");
	}
	print DEST $target_contents;
	close(DEST);
	if ($verbose) {
		print "file ${VTbold}$target${VTnorm} written into configuration directory\n"
	}

	#	lighttpd: LXR server configuration file
	$target = 'lighttpd-lxrserver.conf';
	unless (open(SOURCE, '<', "${tmpldir}/lighttpd/$target")) {
		die("${VTred}ERROR:${VTnorm} couldn't open template file \"${tmpldir}/lighttpd/$target\"\n");
	}
	unless (open(DEST, '>', "${confdir}/${target}")) {
		die("${VTred}ERROR:${VTnorm} couldn't open output file \"${confdir}/$target\"\n");
	}
	#	Expand initial part
	expand_hash	( \*SOURCE
				, \*DEST
				, 'begin_virtroot'
				, \%markers
				, \%option_trans
				, $verbose
				);
	#	Skip virtroot section template
	while (<SOURCE>) {
		last if m/^#\@end_virtroot/;
	}
	#	Expand rest of model
	expand_hash	( \*SOURCE
				, \*DEST
				, '~~~TO~EOF~~~'	# Hope this is never used as a label!
				, \%markers
				, \%option_trans
				, $verbose
				);
	close(SOURCE);
	close(DEST);
	if ($verbose) {
		print "file ${VTbold}$target${VTnorm} written into configuration directory\n"
	}
}
##############################################################
#
#			Configure lxr.conf's global part
#
##############################################################

if (!$addtree) {
	if ($verbose) {
		print "\n";
		print "${VTyellow}***${VTnorm} ${VTred}L${VTblue}X${VTgreen}R${VTnorm} master configuration file setup ${VTyellow}***${VTnorm}\n";
		print "    Global section part\n";
		print "\n";
	}

	my $line;

	open(SOURCE, '<', "${tmpldir}/$lxrtmplconf")
	or die("${VTred}ERROR:${VTnorm} couldn't open template file \"${tmpldir}/$lxrtmplconf\"\n");
	open(DEST, '>', "${confdir}/${confout}")
	or die("${VTred}ERROR:${VTnorm} couldn't open output file \"${confdir}/$confout\"\n");

	#	Expand global section
	expand_hash	( \*SOURCE
				, \*DEST
				, 'begin_tree'
				, \%markers
				, \%option_trans
				, $verbose
				);

	#	Skip tree section template
	while (<SOURCE>) {
		last if m/^#\@end_tree/;
	}

	#	Copy rest of model
	while (<SOURCE>) {
		print DEST;
	}

	close(SOURCE);
	close(DEST);
} elsif ($dbenginechanged && !$nodbuser) {
	if ('n' eq  get_user_choice
				( 'Do you want to create the global DB user?'
				, 1
				, [ 'yes', 'no' ]
				, [ 'y', 'n']
				)
			) {
		$option_trans{'createglobals'} = 0;
	}
}

##############################################################
#
#			Configure lxr.conf's tree-specific part
#		and build shell script for database initialisation
#
##############################################################

if ($verbose) {
	print "\n";
	print "${VTyellow}***${VTnorm} ${VTred}L${VTblue}X${VTgreen}R${VTnorm} master configuration file setup ${VTyellow}***${VTnorm}\n";
	print "    Tree section part\n";
	print "    SQL script for database initialisation\n";
	print "\n";
}

while (1) {
	#	Start each iteration in default configuration
	$option_trans{'add'} = $addtree;
	$option_trans{'dbuseroverride'} = 0;
	delete $markers{'%DB_tree_user%'};
	delete $markers{'%DB_tree_password'};
	delete $markers{'%DB_tbl_prefix%'};

	unless (open(SOURCE, '<', "${tmpldir}/$lxrtmplconf")) {
		die("${VTred}ERROR:${VTnorm} couldn't open template file \"${tmpldir}/$lxrtmplconf\"\n");
	}
	unless (open(DEST, '+<', "${confdir}/${confout}")) {
		die("${VTred}ERROR:${VTnorm} couldn't open output file \"${confdir}/$confout\"\n");
	}

	my $destpos = 0;
	while (<DEST>) {
		if (m/#\@here_tree\n/) {
			last;
		}
		$destpos = tell;
	}
	my @deststat = stat(DEST);
	if ($deststat[7] == $destpos) {
		die("${VTred}ERROR:${VTnorm} couldn't find tree section before EOF in \"${confdir}/$lxrtmplconf\n");
	}
	seek(DEST, $destpos, 0);	# Position for write
		$destpos = tell;

	#	Skip global section model
	while (<SOURCE>) {
		if (m/#\@begin_tree\n/) {
			last;
		}
	}

	#	Expand tree section
	expand_hash	( \*SOURCE
				, \*DEST
				, 'end_tree'
				, \%markers
				, \%option_trans
				, $verbose
				);

	#	Copy rest of model
	while (<SOURCE>) {
		print DEST;
	}

	close(SOURCE);
	close(DEST);

	#	Update lighttpd configuration with the new 'virtroot'
	open(SOURCE, '<', "${tmpldir}/lighttpd/lighttpd-lxrserver.conf")
	or die("${VTred}ERROR:${VTnorm} couldn't open template file \"${tmpldir}/lighttpd/lighttpd-lxrserver.conf\"\n");
	open(DEST, '+<', "${confdir}/lighttpd-lxrserver.conf")
	or die("${VTred}ERROR:${VTnorm} couldn't open configuration file \"${confdir}/lighttpd-lxrserver.conf\"\n");
	#	Position output to variable section
	my $destpos = 0;
	while (<DEST>) {
		if (m/#\@here_virtroot\n/) {
			last;
		}
		$destpos = tell;
	}
	my @deststat = stat(DEST);
	if ($deststat[7] == $destpos) {
		die("${VTred}ERROR:${VTnorm} couldn't find 'virtroot' section before EOF in \"${confdir}/lighttpd-lxrserver.conf\n");
	}
	seek(DEST, $destpos, 0);	# Position for write
		$destpos = tell;
	#	Skip fixed section model
	while (<SOURCE>) {
		if (m/#\@begin_virtroot\n/) {
			last;
		}
	}
	#	Expand virtroot section of model
	expand_hash	( \*SOURCE
				, \*DEST
				, 'end_virtroot'
				, \%markers
				, \%option_trans
				, $verbose
				);
	#	Expand rest of model
	expand_hash	( \*SOURCE
				, \*DEST
				, '~~~TO~EOF~~~'	# Hope this is never used as a label!
				, \%markers
				, \%option_trans
				, $verbose
				);
	close(SOURCE);
	close(DEST);

	#	Have new DB user and password been defined?
	if (exists($markers{'%DB_tree_user%'})) {
		if (exists($users{$markers{'%DB_tree_user%'}})) {
			if ($users{$markers{'%DB_tree_user%'}} ne
					$markers{'%DB_tree_password'}) {
				print "${VTred}ERROR:${VTnorm} user ${VTbold}$markers{'%DB_tree_user%'}${VTnorm} already exists with a different password!\n";
				print "Configuration continues but it won't work.\n";
			}
		} else {
			#	Tell other templates something changed
			$option_trans{'dbuseroverride'} = 1;
			$users{$markers{'%DB_tree_user%'}} = $markers{'%DB_tree_password'};
		}
	}
	#	New DB table prefix?
	if (!exists($markers{'%DB_tbl_prefix%'})) {
		$markers{'%DB_tbl_prefix%'} = $markers{'%DB_global_prefix%'};
	}

	open(SOURCE, '<', "${tmpldir}/initdb/initdb-${dbengine}-template.sql")
	or die("${VTred}ERROR:${VTnorm} couldn't open  script template file \"${tmpldir}/initdb/initdb-${dbengine}-template.sql\"\n");
	if (!$addtree) {
		unlink "${confdir}/${scriptout}";
	};
	open(DEST, '>>', "${confdir}/${scriptout}")
	or die("${VTred}ERROR:${VTnorm} couldn't open output file \"${confdir}/$scriptout\"\n");

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
	close(DEST);
	chmod 0775,"${confdir}/${scriptout}";	# Make sure script has x permission

	print "\n";
	if	(  $cardinality eq 's'
		|| 'n' eq get_user_choice
			( "${VTblue}***${VTnorm} Configure another tree?"
			, 1
			, [ 'yes', 'no' ]
			, [ 'y', 'n']
			)
		) {
		last;
	}
	#	Prevent doing one-time actions more than once
	$addtree = 1;	# Same as adding a new tree
	$option_trans{'createglobals'} = 0;
}

##############################################################
#
#					End of configuration
#
##############################################################

if ($verbose) {
		print "configuration saved in ${VTbold}$confdir/$confout${VTnorm}\n";
		print "DB initialisation sript is ${VTbold}$confdir/$scriptout${VTnorm}\n";
}
