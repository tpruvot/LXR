# -*- tab-width: 4 -*-
###############################################
#
# $Id: Common.pm,v 1.98 2012/08/03 16:33:47 ajlittoz Exp $
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

I<Note:>

=over

I<It initially contained nearly all support routines,
but for the "object" collections (files, index, lang), and was
then correctly the "common" module.
Its size grew beyond maintanability and readability and forced a
split into smaller, specialized modules.
Consequently, its name should be changed to reflect its present
content.>

=back

=cut

package LXR::Common;

$CVSID = '$Id: Common.pm,v 1.98 2012/08/03 16:33:47 ajlittoz Exp $ ';

use strict;

require Exporter;

our @ISA = qw(Exporter);

our @EXPORT = qw(
	$files $index $config
	$HTTP
	$pathname $releaseid $identifier
	&warning &fatal
	&fflush
	&urlargs &nonvarargs &fileref &diffref &idref &incref
	&httpinit &httpclean
);
# our @EXPORT_OK = qw(
#   &abortall 
#   );

# our %EXPORT_TAGS = ('html' => [@EXPORT_OK]);

require Local;
require LXR::SimpleParse;
require LXR::Config;
require LXR::Files;
require LXR::Index;
require LXR::Lang;
require LXR::Template;
require LXRversion;

our $config;
our $files;
our $index;
our $pathname;
our $releaseid;
our $identifier;
our $HTTP;

my $wwwdebug = 0;

# Initial value of temp file counter (see sub tmpcounter below)
my $tmpcounter = 23;


#######################################
#
#	Debugging display functions
#
# HTML display is effective only when $wwwdebug is non zero

# TODO:	update these functions so that they can be used
#		even before sub httpinit has been called to provide
#		a safe and reliable debugging display.
# Hint:	create a flag telling if HTTP headers have already been
#		sent; if not, ouput a minimal set of headers to allow
#		for HTML environment.


=head2 C<warning ($msg)>

Function C<warning> issues a warning message and
returns to the caller.

=over

=item 1 C<$msg>

a I<string> containing the message

=back

The message is prefixed with Perl context information.
It is printed both on STDERR and in the HTML stream.

To prevent HTML mayhem, HTML tag delimiters are replaced by their
entity name equivalent.

=cut

sub warning {
	my $msg = shift;
	my $c = join(", line ", (caller)[ 0, 2 ]);
	print(STDERR "[", scalar(localtime), "] warning: $c: $msg\n");
	$msg =~ s/</&lt;/g;
	$msg =~ s/>/&gt;/g;
	return ("<h4 class=\"warning\"><i>** Warning: $msg</i></h4>\n")
		if $wwwdebug;
	return '';
}


=head2 C<fatal ($msg)>

Function C<fatal> issues an error message and quits.

=over

=item 1 C<$msg>

a I<string> containing the message

=back

Full Perl context information is given
and tentative LXR configuration data is dumped (on STDERR).

The message is printed both on STDERR and in the HTML stream.

B<Notes:>

=over

The message should be protected against HTML abuse by replacing
the HTML tag delimiters by their entity name equivalent.

Since LXR is exited immediately, the HTML stream is not properly
closed. This may cause problem in some browsers.

=back

=cut

sub fatal {
	my $c = join(", line ", (caller)[ 0, 2 ]);
	print(STDERR "[", scalar(localtime), "] fatal: $c: $_[0]\n");
	print(STDERR '[@INC ', join(" ", @INC), ' $0 ', $0, "\n");
	print(STDERR '$config', join(" ", %$config), "\n") if ref($config) eq "HASH";
	print("<h4 class=\"fatal\"><i>** Fatal: $_[0]</i></h4>\n")
		if $wwwdebug;
	exit(1);
}


=head2 C<abortall ($msg)>

Function C<abortall> issues an error message and quits.

=over

=item 1 C<$msg>

a I<string> containing the message

=back

Perl context information is given (on STDERR).

A minimal error page is sent to the user (if $wwwdebug is non zero).

B<Notes:>

=over

The message should be protected against HTML abuse by replacing
the HTML tag delimiters by their entity name equivalent.

=back

=cut

sub abortall {
	my $c = join(", line ", (caller)[ 0, 2 ]);
	print(STDERR "[", scalar(localtime), "] abortall: $c: $_[0]\n");
	print	( "Content-Type: text/html; charset=iso-8859-1\n\n"
			, "<html>\n<head>\n<title>Abort</title>\n</head>\n"
			, "<body><h1>Abort!</h1>\n"
			, "<b><i>** Aborting: $_[0]</i></b>\n"
			, "</body>\n</html>\n"
			)
		if $wwwdebug;
	exit(1);
}


=head2 C<fflush ()>

Function C<fflush> sets STDOUT in autoflush mode.

B<Note:>

=over

This sub is no longer needed and is a candidate for removal.

=back

=cut

sub fflush {
	$| = 1;
	print('');
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

	foreach my $param (keys %{$HTTP->{'param'}}) {
		next unless $param =~ m!^_!;
		my $val = $HTTP->{'param'}->{$param};
		if (length($val)) {
			push(@args, "$param=$HTTP->{'param'}->{$param}");
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
		$args{$1} = $2 if /(\S+)=(\S*)/;
	}
	@args = ();

	foreach ($config->allvariables) {
		$val = $args{$_} || $config->variable($_);
		push(@args, "$_=$val") unless ($val eq $config->vardefault($_));
		delete($args{$_});
	}

	foreach (keys(%args)) {
		push(@args, "$_=$args{$_}");
	}

	return ($#args < 0 ? '' : '?' . join('&', @args));
}


=head2 C<fileref ($desc, $css, $path, $line, @args)>

Function C<fileref> returns an C<< E<lt>AE<gt> >> link to a specific line
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

Notes:

=over

=item 1 All non alphanumeric characters in C<$path> are URL-quoted
to avoid conflicts between unconstrained file name and URL reserved
characters.

=item 1 Since line anchor ids in LXR are at least 4 characters in length,
the line number is eventually extended with zeros on the left.

= item 1 The @args argument is used to pass state and makes use of sub
C<urlargs>.

=back

=cut

sub fileref {
	my ($desc, $css, $path, $line, @args) = @_;

	# jwz: URL-quote any special characters.
	$path =~ s|([^-a-zA-Z0-9.\@/_\r\n])|sprintf("%%%02X", ord($1))|ge;

	if (!defined $line) {
		$line = 0;
	}
	elsif ($line > 0 && length($line) < 4) {
		$line = ('0' x (4 - length($line))) . $line;
	}

	return	( "<a class='$css' href=\"$config->{virtroot}/source$path"
			. &urlargs(@args)
			. ($line > 0 ? "#$line" : "")
			. "\"\>$desc</a>"
			);
}


=head2 C<diffref ($desc, $css, $path, @args)>

Function C<diffref> returns an C<< E<lt>AE<gt> >> link for the first
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

	$path =~ s|([^-a-zA-Z0-9.\@/_\r\n])|sprintf("%%%02X", ord($1))|ge;
	return	( "<a class='$css' href=\"$config->{virtroot}/diff$path"
			. &urlargs	( &nonvarargs()
						, @args
						)
			. "\"\>$desc</a>"
			);
}


=head2 C<idref ($desc, $css, $id, @args)>

Function C<idref> returns an C<< E<lt>AE<gt> >> link to the cross
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
	return ("<a class='$css' href=\"$config->{virtroot}/ident"
		  . &urlargs	( ($id ? "_i=$id" : "")
						, &nonvarargs()
						, @args
						)
		  . "\"\>$desc</a>");
}


=head2 C<incfindfile ($filewanted, $file, @paths)>

Function C<incfindfile> returns the "real" path corresponding to argument
C<$file>.

=over

=item 1 C<$filewanted>

a I<flag> indicating if a directory (0) or file (1) is desired

=item 1 C<$file>

a I<string> containing a file name

=item 1 C<@paths>

an I<array> containing a list of directories to search

=back

The list of directories from configuration parameter C<'incprefix'> is
appended to C<@paths>. Every directory from this array is then preprended
to the file name . The resulting string is transformed by the mapping
rules of configuration parameter C<'maps'> (sub C<mappath>).

If there is a match in the file database (file or directory according
to the first argument), the "physical" path is returned.
Otherwise, an C<undef> is return to signal an unknown file.

I<This is an internal sub only.>

=cut

sub incfindfile {
	my ($filewanted, $file, @paths) = @_;
	my $path;

	push(@paths, $config->incprefix);

	foreach my $dir (@paths) {
		$dir =~ s/\/+$//;
		$path = $config->mappath($dir . "/" . $file);
		if ($filewanted){
			return $path if $files->isfile($path, $releaseid);
		} else {
			return $path if $files->isdir($path, $releaseid);
		}
	}

	return undef;
}


=head2 C<incref ($name, $css, $file, @paths)>

Function C<incref> returns an C<< E<lt>AE<gt> >> link to an C<include>d
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

	$path = incfindfile(1, $file, @paths);
	return undef unless $path;
	return &fileref	( $name
					, $css
					, $path
					);
}


=head2 C<incdirref ($name, $css, $file, @paths)>

Function C<incdirref> returns an C<< E<lt>AE<gt> >> link to a directory
of an C<include>d file or the directory name if it is unknown.

=over

=item 1 C<$name>

a I<string> for the user-visible part of the link,
usually the directory name

=item 1 C<$css>

a I<string> containing the CSS class for the link

=item 1 C<$file>

a I<string> containing the HTML path to the directory

=item 1 C<@paths>

an I<array> containing a list of base directories to search

=back

I<<This function is supposed to be called AFTER sub C<incref> on every
subpath of the include'd file, removing successively the tail directory.
It thus allows to compose a path where each directory is separately
clickable.>>

If the include'd directory does not exist (as determined by sub C<incfindfile>),
the function returns the directory name. This acts as a "no-op" in the
HTML sequence representing the full path of the include'd file.

If the directory exists, the function returns the E<lt>AE<gt> link
as computed by sub C<fileref> for the directory.

=cut

sub incdirref {
	my ($name, $css, $file, @paths) = @_;
	my $path;

	$path = incfindfile(0, $file, @paths);
	return $name unless $path;
	return &fileref	( $name
					, $css
					, $path.'/'
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


=head2 C<fixpaths ($node)>

Function C<fixpaths> fixes its node argument to prevent unexpected
access to files or directories.

=over

=item 1 C<$node>

a I<string> for the path to fix

=back

This is a security function. If the node argument contains any
C</../> part, it is removed with the preceding part.
Also all repeating C</> are replaced by a single slash.

The OS will then be presented only "canonical" paths without access
computation, minimizing the risk of unwanted access.

B<Note:>

=over

Caution! Any use of this sub before full LXR context initialisation
(i.e. before return from sum C<httpinit>) is doomed to fail
because the test for directory type needs a proper value in
C<$releaseid>. This failure is invisible: it does not lead to
run-time error, it just returns a non-sensical status.

=back

=cut

sub fixpaths {
	my $node = shift;
	if (!defined($node)) {
		return "";
	}

	while ($node =~ s|/[^/]+/\.\./|/|g) { }
	$node =~ s|/\.\./|/|g;

	$node .= '/' if $files->isdir($node, $releaseid);
	$node =~ s|//+|/|g;

	return $node;
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
	my $time2 = (stat($config->confpath))[9];
	$time = $time2 if !defined $time or $time2 > $time;

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
		my @days = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun");
		my @months =
		  ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec");
		$year += 1900;
		$wday = $days[$wday];
		$mon  = $months[$mon];

		# Last-Modified: Wed, 10 Dec 1997 00:55:32 GMT
		printf("Last-Modified: %s, %2d %s %d %02d:%02d:%02d GMT\n",
			$wday, $mday, $mon, $year, $hour, $min, $sec);
	}

	if ($HTTP->{'param'}->{'_raw'}) {

		#FIXME - need more types here
		my %type = (
			'gif'  => 'image/gif',
			'html' => 'text/html'
		);

		if ($pathname =~ /\.([^.]+)$/ && $type{$1}) {
			print("Content-Type: ", $type{$1}, "\n");
		} else {
			print("Content-Type: text/plain\n");
		}
	} else {
		print("Content-Type: text/html; charset=", $config->{'encoding'}, "\n");
		print("Cache-Control: no-cache, must-revalidate\n");
	}

	# Close the HTTP header block.
	print("\n");
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

=item 1 tilde (C<~>): differrence C<'variables'>

=item 1 underscore (C<_>): LXR operational parameter

=back

C<httpinit> deals only with the first 2 namespaces.

=cut

sub httpinit {
	$SIG{__WARN__} = \&warning;
	$SIG{__DIE__}  = \&fatal;

	$ENV{'PATH'} = '/bin:/usr/local/bin:/usr/bin:/usr/sbin';

	# Parse and split URL
	$HTTP->{'path_info'} = http_wash($ENV{'PATH_INFO'});

	$HTTP->{'path_info'} = clean_path($HTTP->{'path_info'}) || "";
	$HTTP->{'this_url'} = 'http://' . $ENV{'SERVER_NAME'};
	$HTTP->{'this_url'} .= ':' . $ENV{'SERVER_PORT'}
	  if $ENV{'SERVER_PORT'} != 80;

	$HTTP->{'this_url'} .= $ENV{'SCRIPT_NAME'};
	my $script_path = $HTTP->{'this_url'};
	$script_path =~ s!/[^/]*$!!;

	$HTTP->{'script_path'} = $script_path;

	$HTTP->{'this_url'} .= $HTTP->{'path_info'}
	  if $HTTP->{'path_info'};
	$HTTP->{'this_url'} .= '?' . $ENV{'QUERY_STRING'}
	  if $ENV{'QUERY_STRING'};

	# We don't clean all the parameters here, as some scripts need extended characters
	# e.g. regexp searching
	$HTTP->{'param'} = { map { http_wash($_) } $ENV{'QUERY_STRING'} =~ /([^;&=]+)(?:=([^;&]+)|)/g }
	  if defined $ENV{'QUERY_STRING'};

	# But do clean up these
	$HTTP->{'param'}->{'v'} ||= $HTTP->{'param'}->{'_version'};
	$HTTP->{'param'}->{'a'} ||= $HTTP->{'param'}->{'_arch'};
	$HTTP->{'param'}->{'_i'} ||= $HTTP->{'param'}->{'_identifier'};

	$identifier = clean_identifier($HTTP->{'param'}->{'_i'});
	# remove the param versions to prevent unclean versions being used
	delete $HTTP->{'param'}->{'_i'};
	delete $HTTP->{'param'}->{'_identifier'};

	$config     = LXR::Config->new($script_path);
	unless (defined $config) {
		LXR::Template::makeerrorpage('htmlfatal');
		die "Can't find config for " . $HTTP->{'this_url'};
	}

	# Override the 'variables' value if necessary
	# Effective variable setting is done globally after other init
	foreach my $param (keys %{$HTTP->{'param'}}) {
		my $var = $param;
		next unless $var =~ s/^!//;
		if (exists($config->{'variables'}->{$var})) {
				$HTTP->{'param'}->{$var} = $HTTP->{'param'}->{$param};
		}
		delete $HTTP->{'param'}->{$param};
	}

	$files = LXR::Files->new($config->sourceroot, $config->sourceparams);
	die "Can't create Files for " . $config->sourceroot if !defined($files);
	$index = LXR::Index->new($config->dbname);
	die "Can't create Index for " . $config->dbname if !defined($index);

	# Set variables now
	foreach ($config->allvariables) {
		$config->variable($_, $HTTP->{'param'}->{$_}) if $HTTP->{'param'}->{$_};
		delete $HTTP->{'param'}->{$_};
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
	$config->variable('v', $releaseid);  # put back into config obj
	$pathname   = fixpaths($HTTP->{'path_info'});

	printhttp;
}


=head2 C<clean_release ($releaseid)>

Function C<clean_release> returns its argument if the release exists
otherwise the default value for variable C<'v'>.

=over

=item 1 C<$releaseid>

a I<string> containing the release (version) to check

=back

=cut

sub clean_release {
	my $releaseid = shift;
	my @rels= $config->varrange('v');
	my %test;
	@test{@rels} = undef;

	if(!exists $test{$releaseid}) {
		$releaseid = $config->vardefault('v');
	}
	return $releaseid;
}


=head2 C<clean_identifier ($id)>

Function C<clean_identifier> returns its argument after removing "unusual"
characters.

=over

=item 1 C<$id>

a I<string> representing the identifier

B<Caveat:>

=over

When adding new languages, check that the definition of "unusual" in
this sub does not conflict with the lexical form of identifiers.

=back

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

This erasure is not correct for C</../>.
Moreover, this function is called before C<fixpaths> which then
cannot do its correct job with C</../>.

=back

B<To do:> see if we realy need two (apparently) similar subs

=cut

sub clean_path {
	# Cleans up a string to path
	my $path = shift;

	if(defined $path) {
		# First suppress anything after a dodgy character
	    # Match good chars from start of string,
		# then replace entire string with only good chars
		$path =~ s!(^[\w\s_+\-,\.%\^/\!]+).*!$1!;
		# Clean out /../
		while ($path =~ m!/\.\.?/!) {
			$path =~ s!/\.\.?/!/!g;
		}
	}

	return $path;
}


=head2 C<httpclean ()>

Function C<httpclean> does the final clean up.

To be called when all processing is done, but is it really necessary?

=cut

sub httpclean {
	$config = undef;
	$files  = undef;

	$index->DESTROY();
	$index  = undef;
}

1;
