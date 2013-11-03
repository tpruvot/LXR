# -*- tab-width: 4 -*-
###############################################
#
# $Id: ContextMgr.pm,v 1.3 2013/01/22 16:59:52 ajlittoz Exp $
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

package ContextMgr;

use strict;
use lib do { $0 =~ m{(.*)/}; "$1" };
use QuestionAnswer;
use VTescape;


##############################################################
#
#				Define global parameters
#
##############################################################

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw(
	$cardinality
	$servertype  $scheme   $hostname
	$port        $virtrootbase
	$virtrootpolicy
	$dbengine    $dbenginechanged
	$dbpolicy    $dbname   $dbuser
	$dbpass      $dbprefix $nodbuser
	$nodbprefix
	&contextReload
	&contextSave
	&contextTrees
	&contextDB
	&contextServer
);

	# Single/multiple operation
our $cardinality;

	# Web server
our $servertype;
our $scheme;
our $hostname;
our $port;
our $virtrootbase;
our $virtrootpolicy;

	# Database
our $dbengine;
our $dbenginechanged = 0;
our $dbpolicy;
our $dbname;
our $dbuser;
our $dbpass;
our $dbprefix;
our $nodbuser;
our $nodbprefix;

# WARNING:	remember to increment this number when changing the
#			set of state variables and/or their meaning.
my $context_version = 2;


##############################################################
#
#				Reload context file
#
##############################################################

sub contextReload {
	my ($verbose, $ctxtfile) = @_;
	my $reloadstatus = 0;

	if (my $c=open(SOURCE, '<', $ctxtfile)) {
		print "Initial context $ctxtfile is reloaded\n" if $verbose;
		#	Default record separator
		#	changed to read full file content at once and restored afterwards
		my $oldsep = $/;
		$/ = undef;
		my $context = <SOURCE>;
		$/ = $oldsep;
		close(SOURCE);
		my ($confout) = $context =~ m/\n# Context .* with (.*?)\n/g;
		my $context_created;
		eval($context);
		if (!defined($context_created)) {
			print "${VTred}ERROR:${VTnorm} saved context file probably damaged!\n";
			print "Check variable not found\n";
			print "Delete or rename file $ctxtfile to remove lock.\n";
			exit 1;
		}
		if ($context_created > $context_version) {
			print "${VTyellow}WARNING:${VTnorm} saved context file created with newer version!\n";
			print "Recorded state version = $context_created while expecting version = $context_version\n";
			if ($context_version != $context_created - 1) {
				print "${VTred}ERROR:${VTnorm}Contexts are too different to continue.\n";
				exit 1;
			}
			print "Context are maintained compatible as much as possible.\n";
			print "You may try to continue at your own risk.\n";
			print "\n";
			if ('q' eq get_user_choice
				( 'Do you want to quit or tentatively continue?'
				, 1
				, [ 'quit', 'continue' ]
				, [ 'q', 'c' ]
				) ) {
				exit 1;
			}
		}
		if ($context_created < $context_version) {
			print "${VTred}ERROR:${VTnorm} saved context file too old!\n";
			print "Recorded state version = $context_created while expecting version = $context_version\n";
			if ($context_version == $context_created + 1) {
				print "It is possible to upgrade the context (without saving it),\n";
				print "but without any guarantee.\n";
				print "Note also that templates may have changed and\n";
				print "no longer be compatible with your configuration files.\n";
				print "\n";
				print "${VTyellow}WARNING:${VTnorm} inconsistent answers can lead to LXR malfunction.\n";
				print "\n";
				if ('q' eq get_user_choice
					( 'Do you want to quit or try to upgrade context?'
					, 1
					, [ 'quit', 'upgrade' ]
					, [ 'q', 'u' ]
					) ) {
					exit 1;
					}
				print "\n";
				print "Previous configuration was made for:\n";
				print "- ";
				if ('m' eq $cardinality) {
					print "multiple trees";
				} else {
					print "single tree";
				}
				print "\n";
				print "- ";
				if ('t' eq $dbpolicy) {
					print "per tree";
				} else {
					print "global";
				}
				print " database\n";
				print "\n";
				contextServer (2);
				print "\n";
			} else {
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
				$reloadstatus = 1;
			}
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
				print "Delete or rename file $ctxtfile to remove lock.\n";
				if ('q' eq get_user_choice
					( 'Do you want to quit or manually restore context?'
					, 1
					, [ 'quit', 'restore' ]
					, [ 'q', 'r' ]
					) ) {
					exit 1;
				}
				$reloadstatus = 1;
			};
		}
	} else {
		print "${VTyellow}WARNING:${VTnorm} could not reload context file ${VTbold}$ctxtfile${VTnorm}!\n";
		print "You may have deleted the context file or you moved the configuration\n";
		print "file out of the user-configuration directory without the\n";
		print "context companion file ${VTyellow}$ctxtfile${VTnorm}.\n";
		print "\n";
		print "You can now 'quit' to think about the situation or try to restore\n";
		print "the parameters by answering the following questions\n";
		print "(some clues can be gathered from reading configuration file).\n";
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
		$reloadstatus = 1;
	}
	return $reloadstatus;
}


##############################################################
#
#			Save context for future additions
#
##############################################################

sub contextSave {
	my ($ctxtfile, $confout) = @_;

	if (open(DEST, '>', $ctxtfile)) {
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
	# Initial set in version 1
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
			print DEST "\$dbprefix = '$dbprefix';\n";
		}
	# Set added in version 2
		print DEST "\$servertype = '$servertype';\n";
		print DEST "\$scheme = '$scheme';\n";
		print DEST "\$hostname = '$hostname';\n";
		print DEST "\$port = '$port';\n";
		print DEST "\$virtrootbase = '$virtrootbase';\n";
		print DEST "\$virtrootpolicy = '$virtrootpolicy';\n";
		close(DEST)
		or print "${VTyellow}WARNING:${VTnorm} error $! when closing context file ${VTbold}$confout${VTnorm}!\n";
	} else {
		print "${VTyellow}WARNING:${VTnorm} could not create context file ${VTbold}$confout${VTnorm}, autoreload disabled!\n";
	}
}


##############################################################
#
#				Describe general context
#
##############################################################
#	Are we configuring for single tree or multiple trees?
sub contextTrees {
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
		}
	}
}


##############################################################
#
#				Describe database context
#
##############################################################

sub contextDB {
	my ($verbose) = @_;

	$dbengine =  get_user_choice
			( 'Database engine?'
			, 1
			, [ 'mysql', 'oracle', 'postgres', 'sqlite' ]
			, [ 'm', 'o', 'p', 's' ]
			);

	if ($cardinality eq 's') { 
		$dbpolicy   = 't';
		$nodbuser   = 1;
		$nodbprefix = 1;
	}

	if ($cardinality eq 'm') {
		if ('o' ne $dbengine) {
			if ($verbose > 1) {
				print "The safest option is to create one database per tree.\n";
				print "You can however create a single database for all your trees with a specific set of\n";
				print "tables for each tree (though this is not recommended).\n";
			}
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
			if ($verbose > 1) {
				print "There is only one global database under Oracle.\n";
				print "The tables for each tree are identified by a unique prefix.\n";
			}
			$dbpolicy   = 'g';
			$nodbprefix = 1;
		}
		if ($verbose > 1) {
			print "All databases can be accessed with the same username and\n";
			print "can also be described under the same names.\n";
		}
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
	} elsif ('o' eq $dbengine) {
		$dbpolicy = 'g';
		$nodbuser = undef;
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
#				Describe web server context
#
##############################################################

sub contextServer {
	my ($verbose) = @_;

	if ($verbose > 1) {
		print "LXR can be configured as the default server (the only service in your computer),\n";
		print "a section of this default server or an independent server (with its own\n";
		print "host name).\n";
		print "Refer to the ${VTbold}User's Manual${VTnorm} for a description of the differences.\n";
	}

	$servertype = get_user_choice
			( 'Web server type?'
			, 1
			,	[ "1.default\n"
				, "2.section in default\n"
				, "3.indepedent\n"
				, "4.section in indepedent\n"
				]
			, [ 'D', 'DS', 'I', 'IS' ]
			);
	if ($verbose) {
		print "The computer hosting the server is described by an URL.\n";
		print "The form is scheme://host_name:port\n";
	}
	if ($verbose > 1) {
		print "where:\n";
		print "  - scheme is either http or https (http: can be omitted),\n";
		print "  - host_name can be given as an IP address such as 123.45.67.89\n";
		print "              or a domain name like localhost or lxr.url.example,\n";
		print "  - port may be omitted if standard for the scheme.\n";
		print "The following question asks for a primary URL. Later, you'll have\n";
		print "the opportunity to give aliases to this primary URL.\n";
	}
	my $primaryhost;
	while (!defined($primaryhost)) {
		$primaryhost = get_user_choice
			( '--- Host name or IP?'
			, ('D' eq substr($servertype, 0, 1)) ? -1 : -2
			, [ ]
			, ('D' eq substr($servertype, 0, 1))
				? [ '//localhost' ]
				: [ ]
			);
		$primaryhost =~ m!^(https?:)?(//[^:]+)(?::(\d+))?!;
		$scheme = $1;
		$hostname = $2;
		$port = $3;
		$scheme = undef if 'http:' eq $scheme;
		$port = 80  if !defined($1) && !defined($3);
		$port = 443 if 'https:' eq $1 && !defined($3);
		if (!defined($hostname)) {
			print "${VTred}ERROR:${VTnorm} invalid host name or scheme, try again ...\n";
			$primaryhost = undef;
			next;
		}
		if	(	'I' eq substr($servertype, 0, 1)
			&&	(	'//localhost' eq $hostname
				||	'//127.0.0.1' eq $hostname
				)
			) {
			print "You are configuring for an independent web server and you named it ${hostname},\n";
			print "which is the common name for the default server\n";
			if	( 'y' eq get_user_choice
						( 'Do you want to change its name?'
						, 1
						, [ 'yes', 'no' ]
						, [ 'y', 'n' ]
						)
				) {
				$primaryhost = undef;
			}
		}
	}


	$virtrootbase = '';
	if (1 < length($servertype)) {
		$virtrootbase = get_user_choice
				( 'URL section name for LXR in your server?'
				, -1
				, [ ]
				, [ '/lxr' ]
				);
	}

	if ('m' eq $cardinality) {
		if (1 < $verbose) {
			print "The built-in method to manage several trees with a single instance of LXR is to include\n";
			print "a designation of the tree in the URL at the end of the section name.\n";
			print "This sequence after host name is called \"virtual root\".\n";
			print "Supposing one of your trees is to be referred as \"my-tree\", an URL to list the content\n";
			print "of the default version directory would presently be:\n";
			print "     ${VTyellow}${primaryhost}${virtrootbase}/${VTnorm}${VTbold}my-tree${VTyellow}/source${VTnorm}\n";
			print "with virtual root equal to ${VTyellow}${virtrootbase}/my-tree${VTnorm}\n";
			print "\n";
		}
		$virtrootpolicy = 'b';	# 'b' for built-in
		if	('n' eq get_user_choice
						( 'Use built-in multiple trees management with tree designation at end of virtual root?'
						, 1
						, [ 'yes', 'no' ]
						, [ 'y', 'n' ]
						)
			) {
			$virtrootpolicy = 'c';	# 'c' for custom
		}
	}
}


1;
