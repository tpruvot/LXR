# -*- tab-width: 4 -*-
###############################################
#
# $Id: Common.pm,v 1.111 2014/03/09 15:26:25 ajlittoz Exp $
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
###############################################

=head1 Common module

This module contains HTTP initialisation and various HTML tag generation.

B<Note:>

=over

=item I<It initially contained nearly all support routines
but for the "object" collections (files, index, lang), and was
then correctly the "common" module.
Its size grew beyond maintanability and readability and forced a
split into smaller, specialized modules.
Consequently, its name should be changed to reflect its present
content.>

=back

=cut

package LXR::Common;

$CVSID = '$Id: Common.pm,v 1.111 2014/03/09 15:26:25 ajlittoz Exp $ ';

use strict;

require Exporter;

our @ISA = qw(Exporter);

our @EXPORT = qw(
	$files $index $config
	$HTTP  $HTMLheadOK
	$pathname $releaseid $identifier
	&urlargs &nonvarargs &fileref &diffref &idref &incref
	&httpinit &httpclean
);

require Local;
require LXR::Config;
require LXR::Files;
require LXR::Index;
require LXR::Lang;
require LXR::Template;

our $config;
our $files;
our $index;
our $pathname;
our $releaseid;
our $identifier;
our $HTTP;
our $HTMLheadOK;

# Debugging flag - MUST be set to zero before public release
my $wwwdebug = 1;

# Initial value of temp file counter (see sub tmpcounter below)
my $tmpcounter = 23;

# Flag telling if HTTP headers have sent, thus allowing to emit
# HTML code freely
my $HTTP_inited;


#######################################
#
#	Debugging display functions
#
# HTML display is effective only when $wwwdebug is non zero


=head2 C<warning ($msg)>

Function C<warning> (hook for C<warn> statement)
issues a warning message into the error log
and optionally on screen.

=over

=item 1 C<$msg>

a I<string> containing the message

=back

The message is prefixed with Perl context information.
It is printed on STDERR and if enabled on STDOUT as an HTML fragment.

To prevent HTML mayhem, HTML tag delimiters are replaced by their
entity name equivalent.

I<This function is called after successful initialisation.
There is no need to check for HTTP header state,
since early errors are fatal and handled by the next function.
However, the C<E<lt>HTMLE<gt>> tag and C<E<lt>BODYE<gt>> element
may not yet have been emitted if this is an error on the page header
template.>

B<Note:>

=over

=item

I<Since it proved a valuable debuging aid, the function has been modified
so that it can be used very early in LXR initialisation.
Variable C<$HTMLheadOK> tells if the "standard" header part of the
page has already been sent to screen.
If not, some general purpose header is emitted to support HTML layout
of the warning message.>

I<Of course, when the standard header part is later emitted,
some of its components will be discarded (or not properly set) by the browser
because they occur at an inappropriate location (not HTML-compliant).
This happens only in exceptional circumstances, usually requiring
fix by the LXR administrator.>

=back

=cut

sub warning {
	my $msg = shift;
	my $c = join(', line ', (caller)[ 0, 2 ]);
	print(STDERR '[', scalar(localtime), "] warning: $c: $msg\n");
	if ($wwwdebug) {
		if (!$HTMLheadOK) {
			print '<html><head><title>No LXR Page Header Warning!</title>', "\n";
			print '<base href="', $HTTP->{'host_access'}, $HTTP->{'script_path'}, "/\">\n";
		# Next line in the hope situation is not too bad
			print '<link rel="stylesheet" type="text/css" href="templates/lxr.css">', "\n";
			print '</head>', "\n";
			print '<body>', "\n";
			$HTMLheadOK = 1;
		};
		$msg =~ s/</&lt;/g;
		$msg =~ s/>/&gt;/g;
		$msg =~ s/\n/\n<br>/g;
		print	'<h4 class="warning"><p class="headline">** Warning **</p>'
				. $msg
				. "</h4>\n";
	}
}


=head2 C<fatal ($msg)>

Function C<fatal> (hook for C<die> statement)
issues an error message and quits.

=over

=item 1 C<$msg>

a I<string> containing the message

=back

Full Perl context information is given
and tentative LXR configuration data is dumped (on STDERR).

The message is printed both on STDERR and in the HTML stream.

If variable C<$HTTP_inited> is not set,
HTTP standard headers have not yet been emitted.
In this case, minimal headers and HTML initial elements
(start of stream, C<E<lt>HEADE<gt>> element and start of body)
are printed before the message
and the HTML page is properly closed.

B<Note>:

=over

=item

I<The message may be emitted after the final closing
C<&lt;/HTMLE<gt>> tag if some regular HTML precedes the call
to this subroutine.
This is not HTML-compliant.
Some browsers may complain.>

=back

=cut

sub fatal {
	my $msg = shift;
	my $c = join(', line ', (caller)[ 0, 2 ]);
	print(STDERR '[', scalar(localtime), "] fatal: $c: $msg\n");
	print(STDERR '[@INC ', join(' ', @INC), ' $0 ', $0, "\n");
	print(STDERR '$config', join(' ', %$config), "\n")
		if ref($config) eq 'HASH';
	# If HTTP is not yet initialised, emit a minimal set of headers
	if ($wwwdebug) {
		if (!$HTTP_inited) {
			httpminimal();
			print '<html><head><title>LXR Fatal Error!</title>', "\n";
			print '<base href="', $HTTP->{'host_access'}, $HTTP->{'script_path'}, "/\">\n";
		# Next line in the hope situation is not too bad
			print '<link rel="stylesheet" type="text/css" href="templates/lxr.css">', "\n";
			print '</head>', "\n";
			print '<body>', "\n";
		};
		$msg =~ s/</&lt;/g;
		$msg =~ s/>/&gt;/g;
		$msg =~ s/\n/\n<br>/g;
		print	'<h4 class="fatal"><p class="headline">** Fatal **</p>'
				. $msg
				. "</h4>\n";
		# Properly close the HTML stream
		print '</body></html>', "\n";
	}
	exit(1);
}


=head2 C<tmpcounter ()>

Function C<tmpcounter> returns a unique id for numbering temporary files.

=cut

sub tmpcounter {
	return $tmpcounter++;
}


#######################################
#
#	Link generating functions
#


=head2 C<nonvarargs ()>

Function C<nonvarargs> returns an arrray containing
"key=value" elements from the original URL query string not
related with LXR "variables".

A non "variable" key is identified by its "sigil", an underscore
("_"). Any other key is ignored.

=cut

sub nonvarargs {
	my @args;

	while ((my $param, my $val) = each %{$HTTP->{'param'}}) {
		next unless substr($param, 0, 1) eq '_';
		if (length($val)) {
			push(@args, "$param=$val");
		}
	}

	return @args;
}


=head2 C<urlargs (@args)>

Function C<urlargs> returns a string representing its argument
and the current state of the "variables" set suitable for use
as the query part of an URL.

=over

=item 1 C<@args>

an I<array> containing "key=value" elements

=back

To avoid progressive lengthening of the resulting string, the
"key=value" strings for default variable values are deleted
from the array.

All elements are concatenated with standard ampersand separator
("&") and prefixed with question mark ("?").
This string can be used as is in an URL.

=cut

sub urlargs {
	my @args = @_;
	my %args = ();
	my $val;

	foreach (@args) {
		$args{$1} = $2 if m/(\S+)=(\S*)/;
	}
	@args = ();

	foreach ($config->allvariables) {
		$val = $args{$_} || $config->variable($_);
		push(@args, "$_=$val") unless ($val eq $config->vardefault($_));
		delete($args{$_});
	}

	while ((my $param, $val) = each(%args)) {
		$param = http_encode($param);
		$val   = http_encode($val);
		push(@args, "$param=$val");
	}

	return ($#args < 0 ? '' : '?' . join('&', @args));
}


=head2 C<fileref ($desc, $css, $path, $line, @args)>

Function C<fileref> returns an C<E<lt>AE<gt>> link to a specific line
of a source file.

=over

=item 1 C<$desc>

a I<string> for the user-visible part of the link,
usually the file name

=item 1 C<$css>

a I<string> containing the CSS class for the link

=item 1 C<$path>

a I<string> containing HTML path to the source file

=item 1 C<$line>

an I<integer> containing the line number to reference (or void)

=item 1 C<@args>

an I<array> containing "key=value" elements

=back

B<Notes:>

=over

=item 1 All non alphanumeric characters in C<$path> are URL-quoted
to avoid conflicts between unconstrained file name and URL reserved
characters.

=item 1 Since line anchor ids in LXR are at least 4 characters in length,
the line number is eventually extended with zeros on the left.

=item 1 The @args argument is used to pass state and makes use of sub
C<urlargs>.

=back

=cut

sub fileref {
	my ($desc, $css, $path, $line, @args) = @_;

	# Protect against malicious attacks
	$path = http_encode($path);
	$desc =~ s/&/&amp;/g;
	$desc =~ s/</&lt;/g;
	$desc =~ s/>/&gt;/g;

	$line = ('0' x (4 - length($line))) . $line;

	return	( "<a class='$css' href=\""
				. $config->{'virtroot'}
				. 'source'
				. ( exists($config->{'treename'})
				  ? '/'.$config->{'treename'}
				  : ''
				  )
				. $path
			. &urlargs	( ($HTTP->{'param'}{'_showattic'}
						  ? '_showattic=1'
						  : ''
						  )
						, @args
						)
			. ($line > 0 ? "#$line" : '')
			. "\"\>$desc</a>"
			);
}


=head2 C<diffref ($desc, $css, $path, @args)>

Function C<diffref> returns an C<E<lt>AE<gt>> link for the first
step of difference display selection.

=over

=item 1 C<$desc>

a I<string> for the user-visible part of the link,
usually the file name

=item 1 C<$css>

a I<string> containing the CSS class for the link

=item 1 C<$path>

a I<string> containing the HTML path to the source file

=item 1 C<@args>

an I<array> containing "key=value" elements

=back

But for the C<$line> argument, the interface is identical to sub
C<fileref>'s. See notes above.

Since script C<diff> can be controlled through some URL arguments,
a call is made to sub C<nonvarargs> to keep the values of these
arguments between calls.

=cut

sub diffref {
	my ($desc, $css, $path, @args) = @_;

	# Protect against malicious attacks
	$path = http_encode($path);
	$desc =~ s/&/&amp;/g;
	$desc =~ s/</&lt;/g;
	$desc =~ s/>/&gt;/g;
	return	( "<a class='$css' href=\""
				. $config->{'virtroot'}
				. 'diff'
				. ( exists($config->{'treename'})
				  ? '/'.$config->{'treename'}
				  : ''
				  )
				. $path
			. &urlargs	( &nonvarargs()
						, @args
						)
			. "\"\>$desc</a>"
			);
}


=head2 C<idref ($desc, $css, $id, @args)>

Function C<idref> returns an C<E<lt>AE<gt>> link to the cross
reference list of an identifier.

=over

=item 1 C<$desc>

a I<string> for the user-visible part of the link,
usually the identifier

=item 1 C<$css>

a I<string> containing the CSS class for the link

=item 1 C<$id>

a I<string> containing the name of the identifier to search

=item 1 C<@args>

an I<array> containing "key=value" elements

=back

Since script C<ident> can be controlled through some URL arguments,
a call is made to sub C<nonvarargs> to keep the values of these
arguments between calls.

=cut

sub idref {
	my ($desc, $css, $id, @args) = @_;

	# Protect against malicious attacks
	$id = http_encode($id);
	$desc =~ s/&/&amp;/g;
	$desc =~ s/</&lt;/g;
	$desc =~ s/>/&gt;/g;
	return	( "<a class='$css' href=\""
				. $config->{'virtroot'}
				. 'ident'
				. ( exists($config->{'treename'})
				  ? '/'.$config->{'treename'}
				  : ''
				  )
			. &urlargs	( ($id ? "_i=$id" : '')
						, &nonvarargs()
						, @args
						)
			. "\"\>$desc</a>"
			);
}


=head2 C<incref ($name, $css, $file, @paths)>

Function C<incref> returns an C<E<lt>AE<gt>> link to an C<include>d
file or C<undef> if the file is unknown.

=over

=item 1 C<$name>

a I<string> for the user-visible part of the link,
usually the file name

=item 1 C<$css>

a I<string> containing the CSS class for the link

=item 1 C<$file>

a I<string> containing the HTML path to the include'd file

=item 1 C<@paths>

an I<array> containing a list of base directories to search for the file

=back

If the include'd file does not exist (as determined by sub C<incfindfile>),
the function returns C<undef>.
Otherwise, it returns an E<lt>aE<gt> link as computed by sub C<fileref>.

=cut

sub incref {
	my ($name, $css, $file, @paths) = @_;
	my $path;

	$path = &LXR::Lang::_incfindfile(1, $file, @paths);
	return undef unless $path;
	return &fileref	( $name
					, $css
					, $path
					);
}


#######################################
#
#	HTTP management functions
#


=head2 C<http_wash ($name)>

Function C<http_wash> returns its argument reversing the effect
of a URL-quote.

=over

=item 1 C<$name>

a I<string> to URL-unquote

=back

=cut

sub http_wash {
	my $t = shift;
	if (!defined($t)) {
		return (undef);
	}

	$t =~ s/\%([\da-f][\da-f])/pack("C", hex($1))/gie;

	return ($t);
}


=head2 C<http_encode ($name)>

Function C<http_encode> returns its argument URL-quoted.

=over

=item 1 C<$name>

a I<string> to URL-quote

=back

=cut

sub http_encode {
	my $t = shift;
	return undef if !defined $t;
	$t =~ s|([^-a-zA-Z0-9.@/_~\r\n])|sprintf('%%%02X', ord($1))|ge;
	return $t
}

=head2 C<fixpaths ($node)>

Function C<fixpaths> fixes its node argument to prevent unexpected
access to files or directories.

=over

=item 1 C<$node>

a I<string> for the path to fix

=back

This is a security function. If the node argument contains any
C</../> part, it is removed with the preceding part.
Also C</./> and all repeating C</> are replaced by a single slash.

The OS will then be presented only "canonical" paths without access
computation, minimizing the risk of unwanted access.

B<Note:>

=over

=item

Caution! Any use of this sub before full LXR context initialisation
(i.e. before return from sum C<httpinit>) is doomed to fail
because the test for directory type needs a proper value in
C<$releaseid>. This failure is invisible: it does not lead to
run-time error, it just returns a non-sensical status.

=back

=cut

sub fixpaths {
	my $node = '/' . shift;

	while ($node =~ s|/[^/]+/\.\./|/|g) { }
	$node =~ s|/\.\.?/|/|g;

	$node .= '/' if $files->isdir($node, $releaseid);
	$node =~ s|//+|/|g;

	return $node;
}


=head2 C<httpminimal ()>

Function C<printhttp> ouputs minimal HTTP headers.

=cut

sub httpminimal {
	print 'Content-Type: text/html; charset=utf-8', "\n";
	#Since this a transient error, don't keep it in cache
	print 'Expires: Thu, 01 Jan 1970 00:00:00 GMT', "\n";
	print "\n";
	$HTTP_inited = 1;
}


=head2 C<printhttp ()>

Function C<printhttp> ouputs the HTTP headers.

Presently, only a Last-Modified and a Content-Type header are output.

=cut

sub printhttp {

	# Print out a Last-Modified date that is the larger of: the
	# underlying file that we are presenting (passed in as an
	# argument to this function) and the configuration file lxr.conf.
	# If we can't stat either of them, don't print out a L-M header.
	# (Note that this stats lxr.conf but not lxr/lib/LXR/Common.pm.
	# Oh well, I can live with that I guess...)	-- jwz, 16-Jun-98

	# Made it stat all currently loaded modules.  -- agg.

	my $time = $files->getfiletime($pathname, $releaseid);
	my $time2 = (stat($config->{'confpath'}))[9];
	$time = $time2 if !defined $time || $time2 > $time;

	# Remove this to see if we get a speed increase by not stating all
	# the modules.  Since for most sites the modules change rarely,
	# this is a big hit for each access.

	# 	my %mods = ('main' => $0, %INC);
	# 	my ($mod, $path);
	# 	while (($mod, $path) = each %mods) {
	# 		$mod  =~ s/.pm$//;
	# 		$mod  =~ s|/|::|g;
	# 		$path =~ s|/+|/|g;

	# 		no strict 'refs';
	# 		next unless $ {$mod.'::CVSID'};

	# 		$time2 = (stat($path))[9];
	# 		$time = $time2 if $time2 > $time;
	# 	}

	if ($time > 0) {
		my ($sec, $min, $hour, $mday, $mon, $year, $wday) = gmtime($time);
		my @days = ('Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun');
		my @months =
		  ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
		$year += 1900;
		$wday = $days[$wday];
		$mon  = $months[$mon];

		# Last-Modified: Wed, 10 Dec 1997 00:55:32 GMT
		printf("Last-Modified: %s, %2d %s %d %02d:%02d:%02d GMT\n",
			$wday, $mday, $mon, $year, $hour, $min, $sec);
	}

	if ($HTTP->{'param'}{'_raw'}) {

		#FIXME - need more types here
		my %type =
			( 'gif'  => 'image/gif'
			, 'html' => 'text/html'
			, 'shtml'=> 'text/html'
			);

		if	(	$pathname =~ m/\.([^.]+)$/
			&&	exists($type{$1})
			) {
			print('Content-Type: ', $type{$1}, "\n");
		} else {
			print("Content-Type: text/plain\n");
		}
	} else {
		print('Content-Type: text/html; charset=', $config->{'encoding'}, "\n");
	}

	# Close the HTTP header block.
	print("\n");
	$HTTP_inited = 1;
}


=head2 C<httpinit ()>

Function C<httpinit> parses the URL, cleans up the parameters and sets
up the LXR "variables".

It initializes the global variables (the LXR context) and HTTP output.

Information extracted from URL is stored into I<hash> C<$HTTP>.

This sub is also responsible for HTTP state transition from one
invocation to the other. The URL (query) arguments are spread into
4 name spaces identified by a "sigil":

=over

=item 1 -none-: standard C<'variables'>

=item 1 exclamation mark (C<!>): override C<'variables'> value

=item 1 tilde (C<~>): difference C<'variables'>

=item 1 underscore (C<_>): LXR operational parameter

=back

C<httpinit> deals only with the first 2 namespaces.

=cut

sub httpinit {
	$SIG{__WARN__} = \&warning;
	$SIG{__DIE__}  = \&fatal;
	$HTTP_inited = undef;
	my $olddebug = $wwwdebug;
	$wwwdebug = 1;	# Display something for early errors
					# instead of leaving user with a blank screen

	$ENV{'PATH'} = '/bin:/usr/local/bin:/usr/bin:/usr/sbin';

	# Parse and split URL
	$HTTP->{'path_info'} = http_wash($ENV{'PATH_INFO'});
	$HTTP->{'path_info'} = clean_path($HTTP->{'path_info'});
	$HTTP->{'path_info'} = '/' if $HTTP->{'path_info'} eq '';
	($HTTP->{'path_root'})
		= $HTTP->{'path_info'} =~ m!^/([^/]+)!;

	$HTTP->{'host_access'}  = 'http://' . $ENV{'SERVER_NAME'};
	$HTTP->{'host_access'} .= ':' . $ENV{'SERVER_PORT'}
		if $ENV{'SERVER_PORT'} != 80;

	my $script_path = $ENV{'SCRIPT_NAME'};
# die "server $ENV{'SERVER_SOFTWARE'} - script $ENV{'SCRIPT_NAME'} - path $ENV{'PATH_INFO'}\n";
	# Now, remove script name, to keep only the path (no trailing slash)
	$script_path =~ s!/[^/]*$!!;
	$HTTP->{'script_path'} = $script_path;

	$HTTP->{'this_url'}	= $HTTP->{'host_access'}
						. ( 0 <= index($ENV{'SERVER_SOFTWARE'}, 'thttpd')
						  ?	  $ENV{'SCRIPT_NAME'}
							. $ENV{'PATH_INFO'}
							. ($ENV{'QUERY_STRING'}
							  ? '?'.$ENV{'QUERY_STRING'}
							  : ''
							  )
						  : $ENV{'REQUEST_URI'}
						  );

	# We don't clean all the parameters here, as some scripts need extended characters
	# e.g. regexp searching
	$HTTP->{'param'} =	{ map { s/\+/ /g; http_wash($_) }
							$ENV{'QUERY_STRING'}
								=~ m/([^;&=]+)(?:=([^;&]+)|)/g
						}
		if defined $ENV{'QUERY_STRING'};

	$HTTP->{'param'}{'v'}	||= $HTTP->{'param'}{'_version'};
	$HTTP->{'param'}{'a'}	||= $HTTP->{'param'}{'_arch'};
	$HTTP->{'param'}{'_i'}	||= $HTTP->{'param'}{'_identifier'};
	$identifier = clean_identifier($HTTP->{'param'}{'_i'});

	# remove the param versions to prevent unclean versions being used
	delete $HTTP->{'param'}{'_version'};
	delete $HTTP->{'param'}{'_arch'};
	delete $HTTP->{'param'}{'_i'};
	delete $HTTP->{'param'}{'_identifier'};

	$config = LXR::Config->new	( $HTTP->{'host_access'}
								, $script_path
								, $HTTP->{'path_root'}
								);
	unless (defined $config) {
		$config = LXR::Config->emergency
						( $HTTP->{'host_access'}
						, $script_path
						, $HTTP->{'path_root'}
						);
		httpminimal;
		LXR::Template::makeerrorpage('htmlfatal');
	# There is a race condition under thttpd between STDOUT and STDERR
	# causing debug information (sent to STDOUT) to be printed before
	# HTTP-headers. Consequently, HTML is not interpreted by the
	# browser but displayed as raw data.
		if (0 <= index($ENV{'SERVER_SIGNATURE'}, 'thttpd')) {
			$wwwdebug = 0;	# Avoid double information on display
			die 'Can\'t find config for ' . $HTTP->{'this_url'};
		}
		exit(1);
	}

	# Remove tree name from path_info
	if (exists($config->{'treename'})) {
		$HTTP->{'path_info'} =~ s:^/[^/]+::;
	}

	# Override the 'variables' value if necessary
	# Effective variable setting is done globally after other init
	foreach my $param (keys %{$HTTP->{'param'}}) {
		my $var = $param;
		next unless $var =~ s/^!//;
		if (exists($config->{'variables'}{$var})) {
				$HTTP->{'param'}{$var} = $HTTP->{'param'}{$param};
		}
		delete $HTTP->{'param'}{$param};
	}

	$files = LXR::Files->new($config);
	die 'Can\'t create Files for ' . $config->{'sourceroot'}
		if !defined($files);
	$LXR::Index::database_id++;		# Maybe changing database
	$index = LXR::Index->new($config);
	die 'Can\'t create Index for ' . $config->{'dbname'}
		if !defined($index);

	# Set variables now
	foreach ($config->allvariables) {
		$config->variable($_, $HTTP->{'param'}{$_})
			if exists($HTTP->{'param'}{$_});
		delete $HTTP->{'param'}{$_};
	}

	# Egg-and-hen problem here: clean_release checks the advertised
	# release does exist through a reference {'v'}{'range'} and
	# returns a guaranteed release into $releaseid.
	# {'v'}{'range'} may be a sub needing $pathname.
	# Later fixpaths will canonise this path using $releaseid.
	# To break this vicious circle, we temporarily use the raw
	# path, the only difference being the trailing slash missing
	# on a directory name.
	$pathname   = $HTTP->{'path_info'};
	$releaseid  = clean_release($config->variable('v'));
	$releaseid  =~ m/(.*)/;
	$releaseid  = $1;	# untaint for future use
	$config->variable('v', $releaseid);  # put back into config obj
	$pathname   = fixpaths($HTTP->{'path_info'});
	$pathname   =~ m/(.*)/;
	$pathname   = $1;	# untaint for future use

	printhttp;
	$wwwdebug = $olddebug;	# Safe now
}


=head2 C<clean_release ($releaseid)>

Function C<clean_release> returns its argument if the release exists
otherwise the default value for variable C<'v'>.

=over

=item 1 C<$releaseid>

a I<string> containing the release (version) to check

=back

B<Note:>

=over

=item

This filtering breaks with CVS if a file is not targeted
i.e. directory listing or identifier query.

For a directory, the default release is not a pain, since it is
easy to change it to the desired one as soon as a file is accessed.
The provided release is however kept for the case where directory
display comes from a link in a file and user then jumps to another
file in the directory.
It is assumed that usually user wants both files with same version.  

For identifier query, the provided release MUST be kept, even if it
does not exist, since there is no way in I<ident> to set a
version (all links would then point to default version).

=back

=cut

sub clean_release {
	my $releaseid = shift;

	if	(	!$files->isa('LXR::Files::CVS')
		||	substr($pathname, -1) ne '/'
		) {
		my @rels = $config->varrange('v');
		my %test;
		@test{@rels} = undef;

		if(!exists $test{$releaseid}) {
			$releaseid = $config->vardefault('v');
		}
	}
	return $releaseid;
}


=head2 C<clean_identifier ($id)>

Function C<clean_identifier> returns its argument after removing "unusual"
characters.

=over

=item 1 C<$id>

a I<string> representing the identifier

=back

B<Caveat:>

=over

=item

When adding new languages, check that the definition of "unusual" in
this sub does not conflict with the lexical form of identifiers.

=back

=cut

sub clean_identifier {
	# Cleans up the identifier parameter
	# Result should be HTML-safe and a valid identifier in
	# any supported language...
	# Well, not Lisp symbols since they can contain anything
	my $id = shift;

	$id =~ s/[^\w`:.,\-_ ]//g if defined $id;

	return $id;
}


=head2 C<clean_path ($path)>

Function C<clean_path> returns its argument truncated to known
good characters.

=over

=item 1 C<$path>

a I<string> containing the path to check

The path is truncated at the first non-HTML quote conformant character.
Every sub-path equal to C</./> or C</../> is then removed.

=back

B<Note:>

=over

=item

Is this really necessary since it restricts the user choice of
filenames, even if the set covers the common needs?
All is needed to protect against malicious attacks is to "quote"
HTML reserved characters.

=back

=cut

sub clean_path {
	# Cleans up a string to path
	my $path = shift;

	if(defined $path) {
		# First suppress anything after a dodgy character
	    # Match good chars from start of string,
		# then replace entire string with only good chars
		$path =~ s!(^[\w\s_+\-,\.%\^/\!]+).*!$1!;
		# Clean out /./
		while ($path =~ m!/\./!) {
			$path =~ s!/\./!/!g;
		}
	}

	return $path;
}


=head2 C<httpclean ()>

Function C<httpclean> does the final clean up.

To be called when all processing is done.

=cut

sub httpclean {
	$config = undef;
	$files  = undef;
	$index->final_cleanup();
	$index  = undef;
}

1;
