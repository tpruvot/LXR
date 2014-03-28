# -*- tab-width: 4 -*-
###############################################
#
# $Id: ContextMgr.pm,v 1.6 2014/03/10 10:09:28 ajlittoz Exp $
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
	$servertype  $scheme   $hostname  $port
	@schemealiases  @hostaliases      @portaliases
	$commonvirtroot $virtrootbase     $virtrootpolicy
	$treematch
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

	# Position of tree name
our $treematch;

	# Web server
our $servertype;
our $scheme;
our $hostname;
our $port;
our @schemealiases;
our @hostaliases;
our @portaliases;
our $virtrootbase;
our $commonvirtroot;
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
my $context_version = 3;


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
					print 'multiple trees';
				} else {
					print 'single tree';
				}
				print "\n";
				print "- ";
				if ('t' eq $dbpolicy) {
					print 'per tree';
				} else {
					print 'global';
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

		print "Tree selection mode was: ${VTbold}";
		if ('N' eq $treematch) {
			print 'implicit (single tree)';
		} elsif ('H' eq $treematch) {
			print 'hostname';
		} elsif ('P' eq $treematch) {
			print 'prefix in hostname';
		} elsif ('S' eq $treematch) {
			print 'section name';
		} elsif ('E' eq $treematch) {
			print 'embedded in section';
		} elsif ('A' eq $treematch) {
			print 'argument';
		} else {
			print "???${VTnorm}\n";
			print "${VTred}ERROR:${VTnorm} saved context file damaged or tampered with!\n";
			print "Unknown selection code '$treematch'\n";
			print "Delete or rename file $ctxtfile to remove lock.\n";
			exit 1;
		}
		print "${VTnorm}\n";

		if ($dbpolicy eq 't') {
			print "Your DB engine was: ${VTbold}";
			if ('m' eq $dbengine) {
				print 'MySQL';
			} elsif ('o' eq $dbengine) {
				print 'Oracle';
			} elsif ('p' eq $dbengine) {
				print 'PostgreSQL';
			} elsif ('s' eq $dbengine) {
				print 'SQLite';
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
			print "${VTnorm}\n";
		}

		if	(	's' eq $cardinality
			||	'N' eq $treematch
			) {
			print "${VTred}ERROR:${VTnorm} single tree context not compatible with add mode!\n";
			exit 1;
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
	# @hostaliases added in version 3
		print DEST '@schemealiases = qw( ';
		print DEST join ("\n                   , ", @schemealiases);
		print DEST "\n                   );\n";
		print DEST '@hostaliases = qw( ';
		print DEST join ("\n                 , ", @hostaliases);
		print DEST "\n                 );\n";
		print DEST '@portaliases = qw( ';
		print DEST join ("\n                 , ", @portaliases);
		print DEST "\n                 );\n";
		print DEST "\$treematch = '$treematch';\n";
		print DEST "\$commonvirtroot = $commonvirtroot;\n";
	# Set v2 continued
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
						, [ '^/', 'absolute file path required' ]
						, []
						);
				} else {
					$dbname = get_user_choice
						( 'Name of global database?'
						, -1
						, [ '^\w+$', 'invalid characters in name' ]
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
				, [ '^\w+$', 'invalid characters in name' ]
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
					, [ '^\w+$', 'invalid characters in prefix' ]
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
		print "Many different configurations are possible, they are related to the way\n";
		print "LXR service is accessed, i.e. to the structure of the URL.\n";
		print "Refer to the ${VTbold}User's Manual${VTnorm} for a description of the variants.\n";
	}

	if ($verbose > 1) {
		print "\n";
		print "LXR can be located at the server-root (so called ${VTbold}dedicated${VTnorm})\n";
		print "or lower in the server hierarchy (${VTbold}shared${VTnorm} because there are\n";
		print "usually other pages or sections).\n";
	}
	$servertype = get_user_choice
			( 'Server type?'
			, 2
			,	[ 'dedicated'
				, 'shared'
				]
			, [ 'D', 'S' ]
			);
	if ('m' eq $cardinality) {
		if ($verbose) {
			print "\n";
			print "Selecting which tree to display can be done in various ways:\n";
			print "  1. from the host name (all names are different),\n";
			print "  2. from a prefix to a common host name (similar to previous)\n";
			print "  3. from the site section name (all different)\n";
			print "  4. from interpretation of a section name part (similar to previous)\n";
			print "  5. from the head of script arguments\n";
			if ($verbose > 1) {
				print "Method 5 is highly recommended because it has no impact on webserver\n";
				print "  configuration.\n";
				print "Method 3 is second choice but involves manually setting up many\n";
				print "  symbolic links (one per source-tree).\n";
				print "Method 1 & 2 do not involve symbolic links but need populating webserver\n";
				print "  configuration with virtual hosts.\n";
				print "  Note that method 2 does not work well on //localhost.\n";
				print "Method 4 is deprecated because it has proved not easily portable\n";
				print "  under alternate webservers (other than Apache).\n";
			}
			print "\n";
		}
		$treematch = get_user_choice
			( 'Tree designation?'
			, 1
			,	[ "argument\n"
				, "section name\n"
				, "prefix in host\n"
				, "hostname\n"
				, "embedded in section"
				]
			, [ 'A', 'S', 'P', 'H', 'E' ]	# A arg, S section, P prefix, H host, E = embedded
			);
	} else {
		$treematch = 'N';	# N none
	}
	if	(	'D' eq $servertype
		&&	'S' eq $treematch
		) {
		print "${VTyellow}WARNING:${VTnorm} a dedicated server with tree selection through\n";
		print "  section name is effectively a shared server!\n";
		print "  Server type changed to ${VTyellow}shared${VTnorm}.\n";
		$servertype = 'S';
	}

	if ($verbose) {
		print "\n";
		print "The computer hosting the server is described by an URL.\n";
		print "The form is scheme://host_name:port\n";
	}
	if ($verbose > 1) {
		print "where:\n";
		print "  - scheme is either http or https (http: can be omitted),\n";
		print "  - host_name can be given as an IP address such as 123.45.67.89\n";
		print "              or a domain name like localhost or lxr.url.example,\n";
		print "  - port may be omitted if standard for the scheme.\n";
	}

	if ('H' eq $treematch) {
		print "${VTyellow}Reminder:${VTnorm} Since you chose to give a different hostname\n";
		print "          to every tree, you'll be asked for the hostname when describing\n";
		print "          yours trees.\n";
		print "\n";
		goto END_HOST;
	}
	my $primaryhost;
	if ('P' eq $treematch) {
		print "${VTyellow}Prefix mode:${VTnorm} hostname will later be prefixed with a tree-unique\n";
		print "             prefix defined in the tree descriptions.\n";
		print "${VTred}Important!${VTnorm} Do not use numeric IP in prefix mode.\n";
	}
	while (!defined($primaryhost)) {
		$primaryhost = get_user_choice
			( '--- Host name or IP?'
			, ('H' ne $treematch) ? -1 : -2
			,	[ '^(?i:https?:)?//', 'not an HTTP URL'
				, '//[\w-]+(?:\.[\w-]+)*(?::\d+)?/?$', 'invalid characters in URL'
				]
			, ('H' ne $treematch)
				? [ '//localhost' ]
				: [ ]
			);
		$primaryhost =~ m!^([^/]+)?//([^:]+)(?::(\d+))?/?!;
		$scheme   = $1;
		$hostname = $2;
		$port     = $3;
		$scheme = 'http:' if !defined($1);
		$port   = 80  if 'http:' eq $scheme && !defined($3);
		$port   = 443 if 'https:' eq $1 && !defined($3);
	}
	my $aliashost;
	@schemealiases = ();
	@hostaliases = ();
	@portaliases = ();
	while	('' ne	($aliashost = get_user_choice
									( '--- Alias name or IP?'
									, -3
									, [ '^(?i:https?:)?//', 'not an HTTP URL'
									, '//[\w-]+(?:\.[\w-]+)*(?::\d+)?/?$'
											, 'invalid characters in URL' ]
									, [ ]
									)
					)
			) {;
		$aliashost =~ m!^([^/]+)?//([^:]+)(?::(\d+))?/?!;
		my $aliasscheme = $1;
		my $aliasname   = $2;
		my $aliasport   = $3;
		$aliasscheme = 'http:' if !defined($1);
		$aliasport   = 80  if 'http:' eq $aliasscheme && !defined($3);
		$aliasport   = 443 if 'https:' eq $1 && !defined($3);
		if	(	($aliasscheme ne $scheme)
			||	($aliasport   != $port)
			) {
			print "${VTyellow}Reminder:${VTnorm} scheme: or :port are different on the primary host.\n";
			print "This advanced setting needs manual revision of web-server configuration files.\n";
			print "Otherwise, LXR will answer only on the primary URL\n";
		}
		push (@schemealiases, $aliasscheme);
		push (@hostaliases,   $aliasname);
		push (@portaliases,   $aliasport);
	}
END_HOST:

	$virtrootbase = '';
	$commonvirtroot = 0;
	if	(	'S' eq $servertype
		&&	'S' ne $treematch
		) {
		$virtrootbase = get_user_choice
				( 'URL section name for LXR in your server?'
				, -1
				, [ '^[^\']+$', 'quotes not allowed' ]
				, [ '/lxr' ]
				);
		$virtrootbase =~ s:/+$::;	# Ensure no ending slash
		$virtrootbase =~ s:^/*:/:;	# Ensure a starting slash
		if	(	'E' ne $treematch
			&&	'N' ne $treematch
			) {
			$commonvirtroot =
				'Y' eq get_user_choice
					( 'Will it be shared by all trees?'
					, 1
					, [ 'yes', 'no' ]
					, [ 'Y', 'N']
					);
		}
	}

	if ('E' eq $treematch) {
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
