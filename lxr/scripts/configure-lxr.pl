#!/usr/bin/perl
# -*- tab-width: 4 -*-
###############################################
#
# $Id: configure-lxr.pl,v 1.15 2013/11/07 17:38:36 ajlittoz Exp $
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

# $Id: configure-lxr.pl,v 1.15 2013/11/07 17:38:36 ajlittoz Exp $

use strict;
use Getopt::Long qw(:config gnu_getopt);
use File::Path qw(make_path);
use lib do { $0 =~ m{(.*)/}; "$1" };

use ContextMgr;
use LCLInterpreter;
use QuestionAnswer;
use VTescape;


##############################################################
#
#				Global definitions
#
##############################################################

my $version = '$Revision: 1.15 $';
$version =~ s/Revision: (.*) /$1/;
$version =~ s/\$//g;

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
my ($scriptdir) = $0 =~ m!([^/]+)/[^/]+$!;
my $tmpldir = 'templates';
my $ovrdir  = 'custom.d/templates';
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
				, 'tmpl-ovr=s'	=> \$ovrdir
				, 'verbose:2'	=> \$verbose
				, 'v+'			=> \$verbose
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
      --tmpl-ovr=directory
                  Define template user-override directory
                  (default: $ovrdir)
  -v, --verbose   Explain what is being done
                  full verbosity:   -vv or --verbose,
                  medium verbosity: -v
                  minimal verbosity: none
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
(C) 2012-2013 A. J. Littoz
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
$ovrdir  =~ s:/*$::;
$rootdir =~ s:/*$::;

#	Check LXR environment
my $error = 0;
if (! -d $rootdir) {
	print "${VTred}ERROR:${VTnorm} directory"
		. " ${VTred}$rootdir${VTnorm} does not exist!\n";
	$error = 1;
}
if (! -d $rootdir.'/'.$scriptdir) {
	print "${VTred}ERROR:${VTnorm} ${VTred}$rootdir${VTnorm} does not look "
		. "like an LXR root directory (scripts directory not found)!\n";
	$error = 1;
}
if (! -d $tmpldir) {
	print "${VTred}ERROR:${VTnorm} directory"
		. " ${VTred}$tmpldir${VTnorm} does not exist!\n";
	$error = 1;
}

if (0 <= index($scriptout, '/')) {
	print "${VTred}ERROR:${VTnorm} output script ${VTred}$scriptout${VTnorm} should not contain directory name!\n";
	$error = 1;
}

if (@ARGV > 1) {
	print "${VTred}ERROR:${VTnorm} only one template can be given!\n";
	$error = 1;
}
if (@ARGV == 1) {
	$lxrtmplconf = $ARGV[0];
	if (0 <= index($lxrtmplconf, '/')) {
		print "${VTred}ERROR:${VTnorm} template ${VTred}$lxrtmplconf${VTnorm} should not contain directory name!\n";
	$error = 1;
	}
}
if	(	! -e "$ovrdir/$lxrtmplconf"
	&&	! -e "$tmpldir/$lxrtmplconf"
	) {
	print "${VTred}ERROR:${VTnorm} template file ${VTred}$lxrtmplconf${VTnorm}"
		. " exists neither in override nor in templates directory!\n";
	$error = 1;
}

$confout =  $lxrtmplconf unless defined($confout);
if (0 <= index($confout, '/')) {
	print "${VTred}ERROR:${VTnorm} output configuration ${VTred}$confout${VTnorm} should not contain directory name!\n";
	$error = 1;
}
if (substr($confout, -5) eq '.ctxt') {
	print "${VTred}ERROR:${VTnorm} output configuration file ${VTred}$confout${VTnorm} has a forbidden extension!\n";
	$error = 1;
}
if (substr($confout, -5) ne '.conf') {
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
	print <<END_INTRO;
${VTyellow}***${VTnorm} ${VTred}L${VTblue}X${VTgreen}R${VTnorm} configurator (version: $version) ${VTyellow}***${VTnorm}

LXR root directory is ${VTbold}$rootdir${VTnorm}
Configuration will be stored in ${VTbold}$confdir/${VTnorm}
END_INTRO
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
my %users;			# Cumulative list of all user/password

if ($addtree != 1) {

		#	Single or multiple trees mode of operation
		#	------------------------------------------

	contextTrees ($verbose);

		#	Web server definition
		#	---------------------

	if ($verbose) {
		print "\n";
		print "${VTyellow}***${VTnorm} ${VTred}L${VTblue}X${VTgreen}R${VTnorm} web server configuration ${VTyellow}***${VTnorm}\n";
		print "\n";
	}
	contextServer ($verbose);
	if ('c' eq $virtrootpolicy) {
		print <<END_C_VIRT;
${VTyellow}Reminder:${VTnorm} do not forget to implement your management in the following files:
- ${confdir}/${VTbold}apache-lxrserver.conf${VTnorm} if using Apache,
- ${confdir}/${VTbold}lighttpd-lxrserver.conf${VTnorm} if using lighttpd,
- ${confdir}/${VTbold}${confout}${VTnorm} for parameter 'treeextract'.
It is wise to thoroughly read the Web server chapter in the User's Manual.
END_C_VIRT
		if	('s' eq get_user_choice
						( 'Continue or stop?'
						, 1
						, [ 'continue', 'stop' ]
						, [ 'c', 's' ]
						)
			) {
			exit 0;
		}
	}
}

		#	Choice of database (addition or initial config)
		#	-----------------------------------------------

if ($addtree) {
	if ($verbose) {
		print "== ${VTyellow}ADD MODE${VTnorm} ==\n";
		print "\n";
	}
	$addtree += contextReload ($verbose, "$confdir/$contextfile");
	if ($cardinality eq 's') {
		print "${VTred}ERROR:${VTnorm} initial configuration was done for a single tree!\n";
		print "This is not compatible with the present web server configuration.\n";
		print "To add more trees, you must reconfigure for multiple trees.\n";
		exit 1;
	}
	if ($dbpolicy eq 't') {
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
}

if ($addtree != 1) {
	if ($verbose) {
		print <<END_DB;

${VTyellow}***${VTnorm} ${VTred}L${VTblue}X${VTgreen}R${VTnorm} database configuration ${VTyellow}***${VTnorm}

END_DB
	}
	if ($verbose > 1) {
		print <<END_DB;

The choice of the database engine can make a difference in indexing performance,
but resource consumption is also an important factor.
  * For a small personal project, try ${VTbold}SQLite${VTnorm} which do not
    need a server and is free from configuration burden.
  * For medium to large projects, choice is between ${VTbold}MySQL${VTnorm},
    ${VTbold}PostgreSQL${VTnorm} and Oracle.
    Oracle is not a free software, its interface has not been
    tested for a long time.
  * ${VTbold}PostgreSQL${VTnorm} databases are smaller than MySQL's
    and performance is roughly equivalent.
  * ${VTbold}MySQL${VTnorm} is at its best with large-sized projects
    (such as kernel cross-referencing) where it is fastest at the cost
    of bigger databases.
  * Take also in consideration the number of connected users.
END_DB
	}
	contextDB ($verbose);
	if ($dbuser) {
		$users{$dbuser} = $dbpass;	# Record global user/password
	}
}

##############################################################
#
#			Save context for future additions
#
##############################################################

if (!$addtree) {
	contextSave ("$confdir/$contextfile", $confout);
}

##############################################################
#
#			Set variables needed by the expanders
#
##############################################################

#	%markers contains value for "options" (or their equivalent)
#	which are not meant for substitution in the templates (this
#	is indicated by the _ prefix, but not checked),
#	and "substitution markers".
# From release 1.1 on, both are stuffed in the same hash since
# it simplifies processing in the macro interpreter.
my %markers =
	# Read-only options and parameters
	# (mainly from context)
		( '%_add%'		=> $addtree
		, '%_shell%'	=> 0
		, '%_singlecontext%' => $cardinality eq 's'
		, '%_createglobals%' => $cardinality eq 'm'
							&&	(  0 == $addtree
								|| 1 == $dbenginechanged
								)
		, '%_dbengine%'	=> $dbengine
		, '%_dbpass%'	=> $dbpass
		, '%_dbprefix%'	=> $dbprefix
		, '%_dbuser%'	=> $dbuser
		, '%_dbuseroverride%' => 0
		, '%_globaldb%'	=> $dbpolicy eq 'g'
		, '%_nodbuser%'	=> $nodbuser
		, '%_nodbprefix%' => $nodbprefix
		, '%_virtrootpolicy%' => $virtrootpolicy
		, '%_routing%'	=> $treematch
		, '%_shared%'	=> 'S' eq $servertype
		, '%_commonvirtroot%' => $commonvirtroot

	# Global parameters: directories, server URL
	# (may be overwritten, but not recommended!)
		, '%LXRconfUser%'	=> getlogin	# OS-user running configuration
		, '%LXRroot%'		=> $rootdir
		, '%LXRtmpldir%'	=> $tmpldir
		, '%LXRovrdir%'		=> $ovrdir
		, '%LXRconfdir%'	=> $confdir
		, '%scheme%'		=> $scheme
		, '%hostname%'		=> $hostname
		, '%schemealiases%'	=> \@schemealiases
		, '%hostaliases%'	=> \@hostaliases
		, '%portaliases%'	=> \@portaliases
		, '%port%'			=> $port
		, '%virtrootbase%'	=> $virtrootbase
		);

my $sample;
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
					( '--- Location? (e.g. /usr/share/glimpse-dir/glimpse)'
					, -2
					, [ '^/', 'absolute file path required' ]
					, []
					);
				$markers{'%glimpseindex%'} = get_user_choice
					( '--- Location of indexer? (e.g. /usr/share/glimpse-dir/glimpseindex)'
					, -2
					, [ '^/', 'absolute file path required' ]
					, []
					);
			} else {
				$markers{'%swish%'} = get_user_choice
					( '--- Location? (e.g. /usr/share/swish-dir/swish-e)'
					, -2
					, [ '^/', 'absolute file path required' ]
					, []
					);
			}
		} else {
			print "${VTyellow}Sorry:${VTnorm} free-text search disabled\n";
			$markers{'%glimpse%'} = '/bin/true';	# disable free-text search
			$markers{'%glimpsedirbase%'} = '/tmp';	# only to silence config check
		}
	}

	if	(  defined($markers{'%glimpse%'})
		&& $markers{'%glimpse%'} ne '/bin/true'
		) {
		$markers{'%glimpsedirbase%'} = get_user_choice
					( '--- Directory for glimpse databases?'
					, -2
					, [ '^/', 'absolute file path required' ]
					, []
					);
	}
	if (defined($markers{'%swish%'})) {
		$markers{'%swishdirbase%'} = get_user_choice
					( '--- Directory for swish-e databases?'
					, -2
					, [ '^/', 'absolute file path required' ]
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

sub copy_and_configure_template {
	my ($fin, $fout, $target) = @_;

	my $input = $ovrdir . '/' . $fin;
	if (! -e $input) {
		$input = $tmpldir. '/' . $fin;
	}
	unless (open(SOURCE, '<', $input)) {
		die("${VTred}ERROR:${VTnorm} couldn't open template file \"$input\"\n");
	}
	unless (open(DEST, '>', $fout)) {
		die("${VTred}ERROR:${VTnorm} couldn't open output file \"$fout\n");
	}
	expand_hash	( sub{ <SOURCE> }
				, \*DEST
				, \%markers
				, $verbose
				);
	close(DEST);
	close(SOURCE);
	if ($target && $verbose) {
		print "file ${VTbold}$target${VTnorm} written into ";
		if ($fout eq $target) {
			print 'LXR root';
		} else {
			print 'configuration';
		}
		print " directory\n";
	}
}

if (!$addtree) {
	print "\n" if $verbose;

	chmod(0555, "$tmpldir/Apache/apache2-require.pl");	# Make sure it is executable
# 	chmod(0555, $tmpldir);
# 	if ($verbose) {
# 		print "templates directory ${VTbold}$tmpldir/${VTnorm} now protected read-only\n"
# 	}

	my $target;

	#	Apache: per-directory access control file
	$target = '.htaccess';
	copy_and_configure_template	( 'Apache/htaccess-generic'
								, ${target}
								, $target
								);

	#	Apache: mod_perl startup file
	$target = 'apache2-require.pl';
	copy_and_configure_template	( "Apache/$target"
								, "${confdir}/${target}"
								, ${target}
								);

	#	Apache: LXR server configuration file
	$target = 'apache-lxrserver.conf';
	copy_and_configure_template	( "Apache/$target"
								, "${confdir}/${target}"
								, ${target}
								);

	#	lighttpd: LXR server configuration file
	$target = 'lighttpd-lxrserver.conf';
	copy_and_configure_template	( "lighttpd/$target"
								, "${confdir}/${target}"
								, ${target}
								);

	#	nginx: LXR server configuration file
	$target = 'nginx-lxrserver.conf';
	copy_and_configure_template	( "Nginx/${target}"
								, "${confdir}/${target}"
								, ${target}
								);

	#	thttpd: LXR server configuration file
	$target = 'thttpd-lxrserver.conf';
	copy_and_configure_template	( ${target}
								, "${confdir}/${target}"
								, ${target}
								);

	#	Mercurial: extension and configuration file
	$target = 'hg-lxr-ext.py';
	copy_and_configure_template	( "Mercurial/$target"
								, "${confdir}/${target}"
								);
	$target = 'hg.rc';
	copy_and_configure_template	( "Mercurial/$target"
								, "${confdir}/${target}"
								);
	if ($verbose) {
		print "${VTbold}Mercurial${VTnorm} support files written into configuration directory\n"
	}
}
##############################################################
#
#			Configure lxr.conf's global part
#
##############################################################

if (!$addtree) {
	if ($verbose) {
		print <<END_GLOBAL;

${VTyellow}***${VTnorm} ${VTred}L${VTblue}X${VTgreen}R${VTnorm} master configuration file setup ${VTyellow}***${VTnorm}
    Global section part

END_GLOBAL
	}
	copy_and_configure_template	( $lxrtmplconf
								, "${confdir}/${confout}"
								);
} elsif ($dbenginechanged && !$nodbuser) {
	if ('n' eq  get_user_choice
				( 'Do you want to create the global DB user?'
				, 1
				, [ 'yes', 'no' ]
				, [ 'y', 'n']
				)
			) {
		$markers{'%_createglobals%'} = 0;
	}
}

##############################################################
#
#			Configure lxr.conf's tree-specific part
#		and build shell script for database initialisation
#
##############################################################

if ($verbose) {
	print <<END_TREE;

${VTyellow}***${VTnorm} ${VTred}L${VTblue}X${VTgreen}R${VTnorm} master configuration file setup ${VTyellow}***${VTnorm}
    Tree section part
    SQL script for database initialisation

END_TREE
}

while (1) {
	#	Start each iteration in default configuration
	$markers{'%_add%'} = $addtree;
	$markers{'%_dbuseroverride%'} = 0;
	delete $markers{'%DB_tree_user%'};
	delete $markers{'%DB_tree_password%'};
	delete $markers{'%DB_tbl_prefix%'};

	my $input = $ovrdir . '/' . $lxrtmplconf;
	if (! -e $input) {
		$input = ${tmpldir} . '/' . $lxrtmplconf;
	}
	unless (open(SOURCE, '<', $input)) {
		die("${VTred}ERROR:${VTnorm} couldn't open template file \"${input}\"\n");
	}

	pass2_hash	( \*SOURCE
				, "${confdir}/${confout}"
				, \%markers
				, $verbose
				);

	close(SOURCE);

	#	Update Apache configuration with the new 'virtroot'
	$input = $ovrdir . '/Apache/apache-lxrserver.conf';
	if (! -e $input) {
		$input = ${tmpldir} . '/Apache/apache-lxrserver.conf';
	}
	open(SOURCE, '<', ${input})
	or die("${VTred}ERROR:${VTnorm} couldn't open template file \"${input}\"\n");
	pass2_hash	( \*SOURCE
				, "${confdir}/apache-lxrserver.conf"
				, \%markers
				, $verbose
				);
	close(SOURCE);

	#	Update lighttpd configuration with the new 'virtroot'
	$input = $ovrdir . '/lighttpd/lighttpd-lxrserver.conf';
	if (! -e $input) {
		$input = ${tmpldir} . '/lighttpd/lighttpd-lxrserver.conf';
	}
	open(SOURCE, '<', ${input})
	or die("${VTred}ERROR:${VTnorm} couldn't open template file \"${input}\"\n");
	pass2_hash	( \*SOURCE
				, "${confdir}/lighttpd-lxrserver.conf"
				, \%markers
				, $verbose
				);
	close(SOURCE);

	#	Update Nginx configuration with the new 'virtroot'
	$input = $ovrdir . '/Nginx/nginx-lxrserver.conf';
	if (! -e $input) {
		$input = ${tmpldir} . '/Nginx/nginx-lxrserver.conf';
	}
	open(SOURCE, '<', ${input})
	or die("${VTred}ERROR:${VTnorm} couldn't open template file \"${input}\"\n");
	pass2_hash	( \*SOURCE
				, "${confdir}/nginx-lxrserver.conf"
				, \%markers
				, $verbose
				);
	close(SOURCE);

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
			$markers{'%_dbuseroverride%'} = 1;
			$users{$markers{'%DB_tree_user%'}} = $markers{'%DB_tree_password'};
		}
	}
	#	New DB table prefix?
	if (!exists($markers{'%DB_tbl_prefix%'})) {
		$markers{'%DB_tbl_prefix%'} = $markers{'%DB_global_prefix%'};
	}

	$input = $ovrdir . "/initdb/initdb-${dbengine}-template.sql";
	if (! -e $input) {
		$input = ${tmpldir} . "/initdb/initdb-${dbengine}-template.sql";
	}
	open(SOURCE, '<', ${input})
	or die("${VTred}ERROR:${VTnorm} couldn't open  script template file \"${input}\"\n");
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
	$markers{'%_shell%'} = 1;
	#	Expand script model
	expand_slash_star	( sub{ <SOURCE> }
						, \*DEST
						, \%markers
						, $verbose
						);
	$markers{'%_shell%'} = 0;

	close(SOURCE);
	close(DEST);

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
	$markers{'%_createglobals%'} = 0;
}

##############################################################
#
#					End of configuration
#
##############################################################

chmod 0775, "${confdir}/${scriptout}";	# Make sure script has x permission

#	Since storing files in a VCS does not guarantee adequate permissions
#	are kept, set them explicitly on scripts.
#	We suppose configure-lxr.pl has correct permissions, otherwise we
#	can't bootstrap.
chmod 0775, 'diff', 'genxref', 'ident', 'search', 'showconfig', 'source';
chmod 0775, "${scriptdir}/kernel-vars-grab.sh";
chmod 0775, "${scriptdir}/set-lxr-version.sh";
chmod 0775, "${scriptdir}/recreatedb.pl";
chmod 0775, "${scriptdir}/lighttpd-init";

if ($verbose) {
		print "configuration saved in ${VTbold}$confdir/$confout${VTnorm}\n";
		print "DB initialisation sript is ${VTbold}$confdir/$scriptout${VTnorm}\n";
}
