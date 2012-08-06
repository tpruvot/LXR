# -*- tab-width: 4 -*-
#############################################################
#
# $Id: Template.pm,v 1.0 2011/12/11 09:15:00 ajlittoz Exp $
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

#############################################################

# =encoding utf8	Not recognised??

=head1 Template module

This module is the template expansion engine shared by
the various scripts to display their results in a 
customisable HTML page.

=cut

package LXR::Template;

$CVSID = '$Id: Template.pm,v 1.0 2011/12/11 09:15:00 ajlittoz Exp $';

use strict;

require Exporter;

our @ISA = qw(Exporter);

our @EXPORT = qw(
	gettemplate
	expandtemplate
	makeheader
	makefooter
	makeerrorpage
);
# our @EXPORT_OK = qw();

use LXR::Common;
use LXR::Config;
use LXR::Files;


=head2 C<gettemplate ($who, $prefix, $suffix)>

Function C<gettemplate> returns the contents of the designated
template.
In case the template name has not been defined in lxr.conf or
if the target file does not exist,
an alternate template is generated based on default values
supplied by the arguments.

=over

=item 1 C<$who>

a I<string> containing the template name

=item 1 C<$prefix>

a I<string> containing the head of the alternate template
=item 1 C<$suffix>

a I<string> containing the tail of the alternate prefix

=back

B<Caveat:>

=over

A warning message may be inserted between $prefix and $suffix.
Care must be taken to ensure that this message is placed in the
E<lt>bodyE<gt> part of the HTML page.

I<This> caveat I<is particularly aimed at this sub use in makeheader
where the page has not been started yet.>

=back

=cut

sub gettemplate {
my ($who, $prefix, $suffix) = @_;

	my $template = $prefix;
	if (exists $config->{$who}) {
		if (open(TEMPL, $config->{$who})) {
			local ($/) = undef;
			$template = <TEMPL>;
			close(TEMPL);
		} else {
			$template .= warning
							( "Template file '$who' => '"
							. $config->{$who}
							. "' does not exist"
							);
			$template .= $suffix;
		}
	} else {
		$template .= warning
						( "Template '$who' is not defined"
						);
			$template .= $suffix;
	}
	return $template
}

=head2 C<expandtemplate ($templ, %expfunc)>

Function C<expandtemplate> returns a string where occurrences of
simple template variables and template function parameter blocks
are replaced by their expanded values.

=over

=item 1 C<$templ>

a I<string> containing the template

=item 1 C<%expfunc>

a I<hash> where the key is the variable/function name
and the value is a C<sub> returning the expanded text

=back

The template may contain substitution requests
which are special sequences of characters in the form:

=over

=item * C<$name>

This is a simple variable.
C<$name> will be substituted in the template by the value
returned by the corresponding C<sub> in C<%expfunc>.

=item * C<$name{ ... }>

This is a function.
The fragment between the braces (hereafter called the argument)
is passed as an argument to the corresponding C<sub> in C<%expfunc>.
The returned value is substituted to the whole construct.

B<Notes:>

=over

=item 1 There is no space between the C<$> sign and the
variable/function name.

=item 1 There is no space between the function name and
the opening brace C<{>.

=item 1 The C<name> can contain uppercase and lowercase letters,
digits and undercores.

=back

=back

The content of a function argument is arbitrary.
It may even contain substitution requests as variables or
nested functions.
The only restriction concerns the closing brace C<}>:
it cannot appear inside an argument because it would match
the nearest unmatched opening brace C<{>.
No escape mechanism is presently implemented.
Note, however, that if you are generating HTML you can use &#125;
or &#x7D;.

B<Note:>

=over

=item 1 If the argument contains substitution requests, it is the
C<sub> responsability to interpret them.

The C<sub> may call C<expandtemplate> with the argument as the
new template providing the replacement rules in the new
C<%expfunc>.

=item 1 The C<sub> is free to do whatever it deems appropriate
with the argument.

It can repeateadly call C<expandtemplate>
with changed replacement rules and return the concatenation of
the results. For instance, the replacement rules could scan a
set of values to return the full set of substitutions.

=back

=head3 Algorithm

C<$templ> is repeatedly explored to replace matching C<{> C<}>
(not containing other C<{> C<}>) which are preceded by a single
C<{> by characters C<\x01> and C<\x02> respectively.

I<It proceeds thus from the innermost block to the outermost,
leaving only unnested variables, unnested function calls and
stray unnested braces.>

Then, the C<%expfunc> C<sub>s are called based on the name of
the variables or functions. Variable C<sub>s receive an C<undef>
argument, while function C<sub>s receive the block argument with
its braces restored (or C<undef> if it is empty).
If the variable or function has no corresponding key in C<%expfunc>,
the variable or function call (including its argument) is left
unchanged.

Finally, the leftover C<\x01> and C<\x02> are converted back into { and }.

B<Note:>

=over 4

=item 

I<< This algorithm is implemented through Perl pattern-matching
which is not the most efficient. A better solution would be
a left-to-right parser, avoiding thus backtracking and the
C<{> C<}> to/from C<\x01> C<\x02> fiddling. >

=comment (POD bug?) The end delimiter is voluntarily > instead
 of >> to prevent display of a stray >.

=back

=head3 Extra feature

HTML comments are removed from the template.
However, SSI comments (coded as HTML comments) must not be removed
lest the template would lose its functionality.
Consequently, comments have two forms:

=over 4

=item 1 Normal verbose comments

The opening delimiter (C<< E<lt>!-- >>) MUST be followed by a spacer,
i.e. a space, tab or newline.
The closing delimiter (C<< --E<gt> >>) should also be preceded by a spacer
These comments will be removed.

=item 1 Sticky comments

The start delimiter (C<< E<lt>!-- >>) is immediately followed by a
significant character.
These comments (most notably SSI commands) will be left in the expanded template.

=back

Note that the licence statement in the standard template is written
as verbose comment.
The licence is removed when the template is expanded because the
generated page consists mostly of your private data (either replaced
text or displayed source lines) which certainly are under a different
licence than that of LXR.

=cut

sub expandtemplate {
	my ($templ, %expfunc) = @_;
	my ($expfun, $exppar);

	# Remove the non-sticky comments (see definition above)
	$templ =~ s/<!--\s.*?-->//gs;
	$templ =~ s/\n\n+/\n/gs;

# Proceeding from the innermost to the outermost, replace the
# delimiters of a function call argument by inactive delimiters
# until $templ is left only with unnested function calls.
	while ($templ =~ s/(\{[^\{\}]*)\{([^\{\}]*)\}/$1\x01$2\x02/s) { }
#	                     ^          ^           ^
#	first left brace-----+          |           |
#	nested brace-delimited block----+-----------+
	if (!defined($templ)) {
		return '';
	}
	# Repeatedly find the variables or function calls
	# and apply replacement rule
	$templ =~ s/(\$(\w+)(\{([^\}]*)\}|))/{
		if (defined($expfun = $expfunc{$2})) {
			if ($3 eq '') {
				&$expfun(undef);
			} else {
				$exppar = $4;
				$exppar =~ tr!\x01\x02!\{\}!;
				&$expfun($exppar);
			}
		}
		else {
	# This variable or function has no replacement rule,
	# leave the fragment unchanged in $templ
			$1;
		}
	}/ges;

	# Restore the unused inactive delimiters
	$templ =~ tr/\x01\x02/\{\}/;
	return $templ;
}


=head2 C<targetexpand ($templ, $who)>

Function C<targetexpand> is a "$variable" substitution function.
It returns a string representative of the displayed tree.
The "name" of the tree is extracted from the URL (script-name
component) with the help of the configuration parameter 'treeextract'.

No attempt is made to protect the returned string 

=over

=item 1 C<$templ>

a I<string> containing the template

=over

=item

I<< Presently, the template is equal to C<undef>, which is the
template value for a variable substitution request. >

=comment (POD bug?) See previous =comment about >/>>.

=back

=item 1 C<$who>

a I<string> containing the script name (i.e. source, sourcedir,
diff, ident or search) requesting this substitution

=back

B<Note:>

=over 4

This sub is not fool-proof. It implicitly relies on a
personal convention for multiple trees by the maintainer.
This convention can be defeated by anyone prefering something else.
It is hoped that the C<'treeextract'> parameter mecanism is powerful
enough to cope with any convention.

Should also this parameter be renamed to have some similarity with
this sub? C<'targetextract'> ?

=back

=cut

sub targetexpand {
	my ($templ, $who) = @_;

	# Try to extract meaningful information from the URL
	# Just in case the 'treeextract' pattern is not globally defined,
	# apply a sensible default: tree name before the script-name
	my $treeextract = '([^/]*)/[^/]*$';
	if (exists ($config->{'treeextract'})) {
		$treeextract = $config->{'treeextract'};
	}
	$ENV{'SCRIPT_NAME' } =~ m!$treeextract!;
	my $ret = $1;
	return $ret;
}


=head2 C<captionexpand ($templ, $who)>

Function C<captionexpand> is a "$variable" substitution function.
It returns an HTML-safe string that can be used in a header as a
caption for the page.

=over

=item 1 C<$templ>

a I<string> containing the template

=over

=item

I<< Presently, the template is equal to C<undef>, which is the
template value for a variable substitution request. >

=comment (POD bug?) See previous =comment about >/>>.

=back

=item 1 C<$who>

a I<string> containing the script name (i.e. source, sourcedir,
diff, ident or search) requesting this substitution

=back

=cut

sub captionexpand {
	my ($templ, $who) = @_;

	my $ret = $config->{'caption'}
	# If config parameter is not defined, try to produce
	# a string by extracting a relevant part from the URL.
		|| expandtemplate
				(	"\$tree  by courtesy of the LXR Cross Referencer"
				,	( 'tree'    => sub { targetexpand(@_, $who) }
					)
				);
	$ret =~ s/</&lt;/g;
	$ret =~ s/>/&gt;/g;
	return $ret;
}


=head2 C<bannerexpand ($templ, $who)>

Function C<bannerexpand> is a "$variable" substitution function.
It returns an HTML string displaying the path to the current
file (C<$pathname>) with C<< E<lt>AE<gt> >> links in every portion of
the path to allow quick access to the intermediate directories.

=over

=item 1 C<$templ>

a I<string> containing the template

=over

=item

I<< Presently, the template is equal to C<undef>, which is the
template value for a variable substitution request. >

=comment (POD bug?) See previous =comment about >/>>.

=back

=item 1 C<$who>

a I<string> containing the script name (i.e. source, sourcedir,
diff, ident or search) requesting this substitution

=back

=cut

sub bannerexpand {
	my ($templ, $who) = @_;

	# Substitution is meaningful only for scripts dealing with files
	if ($who eq 'source' || $who eq 'sourcedir' || $who eq 'diff') {
		my $fpath = '';
	# Instead of an empty root, put there the name of the tree
		my $furl  = fileref($config->sourcerootname . '/', "banner", '/');

	# Process each intermediate directory
		foreach ($pathname =~ m!([^/]+/?)!g) {
			$fpath .= $_;
	# To have a nice string, insert a zero-width space after each /
	# so that it's possible for the pathnames to wrap.
			$furl .= '&#x200B;' . fileref($_, "banner", "/$fpath");
		}
	# We captured above the intermediate directory with both start
	# and end delimiters. To avoid display of duplicate delimiters
	# remove the end delimiter (since we forced a start delimiter)
	# inside the <a> comment block.
		$furl =~ s!/</a>!</a>/!gi;

		return "<span class=\"banner\">$furl</span>";
	} else {
		return '';
	}
}


=head2 C<titleexpand ($templ, $who)>

Function C<titleexpand> is a "$variable" substitution function.
It returns an HTML-safe string suitable for use in a C<< <title> >>
element.

=over

=item 1 C<$templ>

a I<string> containing the template

=over

=item

I<< Presently, the template is equal to C<undef>, which is the
template value for a variable substitution request. >

=comment (POD bug?) See previous =comment about >/>>.

=back

=item 1 C<$who>

a I<string> containing the script name (i.e. source, sourcedir,
diff, ident or search) requesting this substitution

=back

=cut

sub titleexpand {
	my ($templ, $who) = @_;
	my $ret;

	if ($who eq 'source' || $who eq 'diff' || $who eq 'sourcedir') {
		$ret = $config->sourcerootname . $pathname;
	} elsif ($who eq 'ident') {
		my $i = $HTTP->{'param'}->{'_i'};
		$ret = $config->sourcerootname . ' identifier search'
				. ($i ? ": $i" : '');
	} elsif ($who eq 'search') {
		my $s = $HTTP->{'param'}->{'_string'};
		$ret = $config->sourcerootname . ' general search'
				. ($s ? ": $s" : '');
	}
	$ret =~ s/</&lt;/g;
	$ret =~ s/>/&gt;/g;
	return $ret;
}


=head2 C<stylesheet ($templ)>

Function C<thisurl> is a "$variable" substitution function.
It returns an HTML-encoded string suitable for use as the
target href of a C<< E<lt>link rel="stylesheet"E<gt> >> tag.

=over

=item 1 C<$templ>

a I<string> containing the template (i.e. argument)

=over

=item

I<< Presently, the template is equal to C<undef>, which is the
template value for a variable substitution request. >

=comment (POD bug?) See previous =comment about >/>>.

=back

The string comes from configuration parameter C<'stylesheet'>.

=cut

sub stylesheet {
	my $ret = $config->{'stylesheet'};

	$ret =~ s/([\?\&\;\=\'\"])/sprintf('%%%02x',(unpack('c',$1)))/ge;
	return $ret;
}


=head2 C<altstyleexpand ($templ, $who)>

Function C<altstyleexpand> is a "$function" substitution function.
It returns an HTML string which is the concatenation of its
expanded argument applied to all the alternate stylesheet definitions
found in the configuration file.

=over

=item 1 C<$templ>

a I<string> containing the template (i.e. argument)

=item 1 C<$who>

a I<string> containing the script name (i.e. source, sourcedir,
diff, ident or search) requesting this substitution;
it is here considered as the "mode"

=back

=head3 Algorithm

It retrieves the configuration array 'alternate_stylesheet'
if it exists.

The argument template is then expanded through C<expandtemplate>
for each URL argument with a replacement rule for its name and value.

=cut

sub altstyleexpand {
	my ($templ, $who) = @_;
	my $altex;

	if (exists $config->{'alternate_stylesheet'}) {
		for my $sheet (@{$config->{'alternate_stylesheet'}}) {
			$altex .= expandtemplate
						( $templ
						,	( 'stylesheet' => sub { $sheet }
							, 'stylename' =>
								sub { my $nm = $sheet;
									  $nm =~ s/\.[^.]*$//;
									  return $nm
									}
							)
						);
		}
	}

	return ($altex);
}

=head2 C<thisurl ()>

Function C<thisurl> is a "$variable" substitution function.
It returns an HTML-encoded string suitable for use as the
target href of a C<< E<lt>AE<gt> >> tag.

The string is the URL used to access the current page (complete
with the ?query string).

=cut

sub thisurl {
	my $url = $HTTP->{'this_url'};

	$url =~ s/([\?\&\;\=\'\"])/sprintf('%%%02x',(unpack('c',$1)))/ge;
	return $url;
}


=head2 C<baseurl ()>

Function C<baseurl> is a "$variable" substitution function.
It returns an HTML-encoded string suitable for use as the
target href of a C<< E<lt>AE<gt> >> or C<< E<lt>baseE<gt> >> tag.

The string is the base URL used to access the LXR server.

=cut

sub baseurl {
	(my $url = $config->baseurl) =~ s!/*$!/!;

	$url =~ s/([\?\&\;\=\'\"])/sprintf('%%%02x',(unpack('c',$1)))/ge;
	return $url;
}


=head2 C<dotdoturl ()>

Function C<dotdoturl> is a "$variable" substitution function.
It returns an HTML-encoded string suitable for use as the
target href of a C<< <a> >> or C<< <base> >> tag.

The string is the ancestor of the base URL used to access the
LXR server.

=cut

#ajl111211 Is this function meaningful?
# This ../ can be unreachable, depending on the way
# DocumentRoot is configured
sub dotdoturl {
	my $url = $config->baseurl;
	$url =~ s!/$!!;
	$url =~ s!/[^/]*$!/!;	# Remove last directory
	$url =~ s/([\?\&\;\=\'\"])/sprintf('%%%02x',(unpack('c',$1)))/ge;
	return $url;
}


=head2 C<forestexpand ($templ, $who)>

Function C<forestexpand> is a "$function" substitution function.
It returns an HTML string which contains links to the shareable trees
of the configuration file.

=over

=item 1 C<$templ>

a I<string> containing the template (i.e. argument)

=item 1 C<$who>

a I<string> containing the script name (i.e. source, sourcedir,
diff, ident or search) requesting this substitution

=back

=head3 Algorithm

It reads the configuration file into an array.

The elements, except the first (index 0), are scanned to see
if parameter 'shortcaption' is defined,
which means this tree is shareable.

If none is found, the template is not expanded.
The returned string is void, thus avoiding any stray legend
in the page.

Otherwise, the argument template is then expanded
through C<expandtemplate> with a replacement rule for theœ
C<'treelinks'> attribute.

=cut

sub forestexpand {
	my ($templ, $who) = @_;
	my @configgroups = $config->readconfig();
	my $trex;

	# Scan the parameter groups for 'shortcaption'
	# to see if there is at least one shareable tree.
	my $shareable = 0;
	foreach my $group (@configgroups[1..$#configgroups]) {
		++$shareable if exists($group->{'shortcaption'});
	}
	# No shareable tree or only one, return a void string to
	# wipe out any fixed text (titles, captions, ...)
	return '' if ($shareable<2);
	# Shareable trees exist, do the job
	$trex .= expandtemplate
				(	$templ
				,	( 'trees' => sub { treesexpand(@_, $who, @configgroups) }
					)
				);

	return ($trex);
}


=head2 C<treesexpand ($templ, $who, $var)>

Function C<treesexpand> is a "$function" substitution function.
It returns an HTML string which is the concatenation of its
expanded argument applied to all the shareable trees of the
configuration file.

=over

=item 1 C<$templ>

a I<string> containing the template (i.e. argument)

=item 1 C<$who>

a I<string> containing the script name

=item 1 C<$confgroups>

a I<array> containing a copy of the configuration file

=back

=head3 Algorithm

It uses the copy of the configuration file passed as an array argument.

The elements, except the first (index 0), are scanned to see
if parameter 'shortcaption' is defined,
which means this tree is shareable.
Parameters C<'host_names'> and C<'virtroot'> are retrieved to build
an URL to launch LXR on that tree.

C<'virtroot'> is supposed to be unique for each tree.
C<'host_names'>, if not locally defined, is fetched from the global
parameters (index 0 element).

The presently used hostname is extracted from the URL.
If it exists in the C<'host_names'> list, it is used for the link.
Otherwise, the first name is used.

If this is the case, the argument template is then expanded
through C<expandtemplate> with a replacement rule for each attribute.

The result is the concatenation of the repeated expansion.

No attempt is made to use C<'baseurl'> or  C<'baseurl_aliases'>

B<Potential problem:>

=over

The LXR server may be accessed simultaneously under different names,
e.g. C<localhost> on the computer, a short name on the LAN and a full
URL from the Net.

Choosing the first name in C<'host_names'> may not give the correct name
for the current user (C<localhost> instead of a fully qualified URL).
But extracting the hostname from the page URL is not guaranteed to
be the correct choice in all circumstances.

This might be solved with a more complex structure in C<'host_names'>
made of 2 lists, one for "local" mode, the other for "remote" mode.
But, once again, how to chose reliably and automatically the correct
option?

With these two lists, an approach could be to note the index of the
hostname for the successfully identified trees.
If it is always the same, then determine if this is a local or remote
hostname and use the first hostname in the corresponding list for
the unknown tree.

=back

=cut

sub treesexpand {
	my ($templ, $who, @confgroups) = @_;
	my $tlex;
	my $treelink;
	my $global = shift @confgroups;

	$who =~ s/^sourcedir$/source/;
	my ($accesshost, $accessport) =
		$HTTP->{'script_path'} =~ m!(^.+?://[^/:]+)(:\d+)?!;
	(my $scriptpath =$HTTP->{'script_path'}) =~ s!(^.+?://[^/:]+)(:\d+)?!$1!;

	# Scan the configuration groups, skipping non-shareable trees
	for my $group (@confgroups) {
		next unless exists($group->{'shortcaption'});
		my $shortcap =  $group->{'shortcaption'};
		my $virtroot =  $group->{'virtroot'};
		my @hosts = @{$group->{'host_names'} || $global->{'host_names'}};
		my $url;
		my $port;
		for my $hostname (@hosts) {
			$hostname =~ s!/*$!!;		# remove trailing /
			$hostname =~ s/(:\d+)$//;	# remove port
			my $port = $1;
	# Add http: if it was dropped in the hostname
			if ($hostname !~ m!^.+?://!) {
				$hostname = "http:" . $hostname;
			}
			$url = $hostname.$virtroot;
	# Is this the presently used hostname?
			last if $url eq $scriptpath;
			$url = undef;
		}
		if (defined($url)) {
	# The current tree has been found, give it a highlight
			$treelink = "<span class=\"tree-sel\">$shortcap</span>";
		} else {
	# This is an alternate tree, try to see if the current hostname
	# is on the list for this tree
			my $the_host = quotemeta($accesshost);
			$url = undef;
			for my $hostname (@hosts) {
				$hostname =~ s!/*$!!;		# remove trailing /
				$hostname =~ s/(:\d+)$//;	# remove port
				$port = $1;
	# Add http: if it was dropped in the hostname
				if ($hostname !~ m!^.+?://!) {
					$hostname = "http:" . $hostname;
				}
				if ($hostname eq $accesshost) {
					$url = $hostname;
					last;
				}
			}
	# The current hostname is not on the list for this tree.
	# Take the first name but NOTE it is not reliable
			if (!defined($url)) {
				$url = $group->{'host_names'}->[0]
					|| $global->{'host_names'}->[0];
				$url =~ s/(:\d+)$//;
				$port = $1;
			}
	# If a port is given on 'host_names', use it.
	# Otherwise, use the incoming request port
			$url .= $port || $accessport;
			$url = "http:" . $url unless ($url =~ m!^.+?://!);
			$treelink =
				"<a class=\"treelink\" href=\"$url$virtroot/$who\">$shortcap</a>";
		}
		$tlex .= expandtemplate
					( 	$templ
					,	( 'caption' => sub { $shortcap }
						, 'link' => sub { $url }
				# NOTE $caption and $link are reserved for future
				# extensions and must not be used in templates
				# as their semantics is not well defined
						, 'treelink' => sub { $treelink }
						)
					);
	}
	return $tlex;
}


=head2 C<urlexpand ($templ, $who)>

Function C<urlexpand> is a "$function" substitution function.
It returns an HTML string which is the concatenation of its
expanded argument applied to all the URL arguments of the
current page.

=over

=item 1 C<$templ>

a I<string> containing the template (i.e. argument)

=item 1 C<$who>

a I<string> containing the script name (i.e. source, sourcedir,
diff, ident or search) requesting this substitution;
it is here considered as the "mode"

=back

=head3 Algorithm

It makes use of sub C<urlargs> to retrieve the filtered list of
variables values.
If necessary, other URL arguments may be added depending on the mode
(known from C<$who>.

The argument template is then expanded through C<expandtemplate>
for each URL argument with a replacement rule for its name and value.

=cut

sub urlexpand {
	my ($templ, $who) = @_;
	my $urlex;
	my $args;

	# diff needs special processing: the currently selected version
	# of the file is transfered with a set of "mirror" arguments
	# (their name is the same as a variable with a ~ prefix),
	# so that the standard selection mechanism will give
	# the version to compare to in the current value of the variables.
	if ($who eq 'diff') {
		my @args = ();
		foreach ($config->allvariables) {
			push(@args, "~$_=".$config->variable($_));
		}
		diffref ("", "", $pathname, @args) =~ m!^.*?(\?.*?)"!;
		$args = $1;
	} else {
		$args = &urlargs();
	}

	while ($args =~ m![?&;]((?:\~|\w)+)=(.*?)(?=[&;]|$)!g) {
		my $var = $1;
		my $val = $2;
		$urlex .= expandtemplate
					( $templ
					,	( 'urlvar' => sub { $var }
						, 'urlval' => sub { $val }
						)
					);
	}

	return ($urlex);
}


=head2 C<modeexpand ($templ, $who)>

Function C<modeexpand> is a "$function" substitution function.
It returns an HTML string which is the concatenation of its
expanded argument applied to all the LXR modes.

=over

=item 1 C<$templ>

a I<string> containing the template (i.e. argument)

=item 1 C<$who>

a I<string> containing the script name (i.e. source, sourcedir,
diff, ident or search) requesting this substitution;
it is here considered as the "mode"

=back

=head3 Algorithm

It first constructs a list (Perl C<@>vector) of hashes describing
the state of the mode: its name, selection state, link or action,
CSS class.

The argument template is then expanded through C<expandtemplate>
for each mode with a replacement rule for each attribute.

The result is the concatenation of the repeated expansion.

=cut

sub modeexpand {
	my ($templ, $who) = @_;
	my $modex;
	my $mode;
	my @mlist = ();
	my $modelink;
	my $modename;
	my $modecss;
	my $modeaction;
	my $modeoff;

	$modename = "Source navigation";
	if ($who eq 'source' || $who eq 'sourcedir')
	{	$modelink = "<span class='modes-sel'>$modename</span>";
		$modecss  = "modes-sel";
		$modeaction= "";
		$modeoff  = "disabled";
	} else {
		$modelink = fileref($modename, "modes", $pathname);
		$modecss  = "modes";
		$modelink =~ m!href="(.*?)(\?|">)!;	# extract href target as action
		$modeaction = "$config->{virtroot}/source";
		$modeoff  = "";
	}
	push(@mlist,	{ 'name' => $modename
					, 'link' => $modelink
					, 'css'  => $modecss
					, 'action'=> $modeaction
					, 'off'  => $modeoff
					}
		);

	$modename = "Diff markup";
	if ($who eq 'diff')
	{	$modelink = "<span class='modes-sel'>$modename</span>";
		$modecss  = "modes-sel";
		$modeaction= "";
		$modeoff  = "disabled";
		push(@mlist,	{ 'name' => $modename
						, 'link' => $modelink
						, 'css'  => $modecss
						, 'action'=> $modeaction
						, 'off'  => $modeoff
						}
			);
	} elsif ($who eq 'source' && $pathname !~ m|/$|) {
		$modelink = diffref($modename, "modes", $pathname);
		$modecss  = "modes";
		$modelink =~ m!href="(.*?)(\?|">)!;	# extract href target as action
		$modeaction = $1;
		$modeoff  = "";
		push(@mlist,	{ 'name' => $modename
						, 'link' => $modelink
						, 'css'  => $modecss
						, 'action'=> $modeaction
						, 'off'  => $modeoff
						}
			);
	}

	$modename = "Identifier search";
	if ($who eq 'ident')
	{	$modelink = "<span class='modes-sel'>$modename</span>";
		$modecss  = "modes-sel";
		$modeaction= "";
		$modeoff  = "disabled";
	} else {
		$modelink = idref($modename, "modes", "");
		$modecss  = "modes";
		$modeaction = "$config->{virtroot}/ident";
		$modeoff  = "";
	}
	push(@mlist,	{ 'name' => $modename
					, 'link' => $modelink
					, 'css'  => $modecss
					, 'action'=> $modeaction
					, 'off'  => $modeoff
					}
		);

	$modename = "General search";
	if ($who eq 'search')
	{	$modelink = "<span class='modes-sel'>$modename</span>";
		$modecss  = "modes-sel";
		$modeaction= "";
		$modeoff  = "disabled";
	} else {
		$modelink = "<a class=\"modes\" "
					. "href=\"$config->{virtroot}/search"
					. urlargs
					. "\">general search</a>";
		$modecss  = "modes";
		$modeaction = "$config->{virtroot}/search";
		$modeoff  = "";
	}
	push(@mlist,	{ 'name' => $modename
					, 'link' => $modelink
					, 'css'  => $modecss
					, 'action'=> $modeaction
					, 'off'  => $modeoff
					}
		);

	foreach $mode (@mlist) {
		$modename = $$mode{'name'};
		$modelink = $$mode{'link'};
		$modecss  = $$mode{'css'};
		$modeaction = $$mode{'action'};
		$modeoff  = $$mode{'off'};
		$modex .= expandtemplate
					( $templ
					,	( 'modelink' => sub { $modelink }
						, 'modecss'  => sub {  $modecss }
						, 'modeaction' => sub { $modeaction }
						, 'modeoff'  => sub { $modeoff }
						, 'modename' => sub { $modename }
						, 'urlargs' => sub { urlexpand (@_, $who) }
						)
					);
	}

	return ($modex);
}


=head2 C<varlinks ($templ, $who, $var)>

Function C<varlinks> is a "$function" substitution function.
It returns an HTML string which is the concatenation of its
expanded argument applied to all the values of $var.

=over

=item 1 C<$templ>

a I<string> containing the template (i.e. argument)

=item 1 C<$who>

a I<string> containing the script name

=item 1 C<$var>

a I<string> containing the name of a configuration variable
(defined in the C<'variables'> configuration parameter)

=back

=head3 Algorithm

It first constructs a list (Perl C<@>vector) made of HTML
fragments describing the values of the variable (with an
indication of the current value).

The argument template is then expanded through C<expandtemplate>
for each value with a replacement rule allowing the inclusion of
the HTML fragment.

The result is the concatenation of the repeated expansion.

B<Note:>

=over

If the current target directory or file was selected by an
'include' link, the path must be recomputed with the new
variable value.
Theoretically, we should restart the whole process from the fragments
in the include directive, which is no longer known at this stage.
Though _file and _dir arguments have been added in the URL to allow
accurate computation in all circumstances,
we don't use them in this version.
Instead, we assume that 'maps' transformation is not that twisted
as to need a recomputation from start.
That is, we assume that reapplying the 'maps' transformation a second
time with a different variable value will undo the first application
and give the correct result.

This is not guaranteed to work always.

=back

=cut

sub varlinks {
	my ($templ, $who, $var) = @_;
	my $vlex = '';
	my ($val, $oldval);
	my $vallink;
	my $cnt = 0;
	my @dargs;

	# diff needs special processing: the currently selected version
	# of the file is transfered with a set of "mirror" arguments
	# (their name is the same as a variable with a ~ prefix),
	# so that the standard selection mechanism will give
	# the version to compare to in the current value of the variables.
	if ($who eq 'diff') {
		foreach ($config->allvariables) {
			push(@dargs, "~$_=".$config->variable($_));
		}
	}

	$oldval = $config->variable($var);
	foreach $val ($config->varrange($var)) {
		if ($val eq $oldval) {
			$vallink = "<span class=\"var-sel\">$val</span>";
		} else {
			if ($who eq 'source' || $who eq 'sourcedir') {
				$vallink = &fileref	( $val
									, "varlink"
									, $config->mappath($pathname, "$var=$val")
									, 0
									, "$var=$val"
									);

			} elsif ($who eq 'diff') {
				$vallink = &diffref($val, "varlink", $pathname, "$var=$val", @dargs);
			} elsif ($who eq 'ident') {
				$vallink = &idref($val, "varlink", $identifier, "$var=$val");
			} elsif ($who eq 'search') {
				$vallink =
				    "<a class=\"varlink\" href=\"$config->{virtroot}/search"
				  . &urlargs("$var=$val", "_string=" . $HTTP->{'param'}->{'_string'})
				  . "\">$val</a>";
			}
		}

		$vallink = "[" . $vallink . "]";

		$cnt++;
		if (($cnt % 6) eq 0) {
			$vallink = $vallink . "&nbsp;<br/>";
		}

		$vlex .= expandtemplate
					( $templ
					, ('varvalue' => sub { $vallink })
					);
	}
	return ($vlex);
}


=head2 C<varmenuexpand ($var)>

Function C<varmenuexpand> is a "$function" substitution function.
It returns an HTML string which is the concatenation of
C<< E<lt>optionE<gt> >> tags, each one corresponding to the values
defined in variable $var's 'range'.

=over

=item 1 C<$templ>

a I<string> containing the template (i.e. argument)

=item 1 C<$var>

a I<string> containing the variable name

=back

=cut

sub varmenuexpand {
	my ($templ, $who, $var) = @_;
	my $val;
	my $class;
	my $sel;
	my $menuex;

	my $oldval = $config->variable($var);
	foreach $val ($config->varrange($var)) {
		if ($val eq $oldval) {
			$class = "var-sel";
			$sel = "selected";
		} else {
			$class = "varlink";
			$sel = "";
		}

		$menuex .= expandtemplate
					( $templ
					,	( 'itemclass' => sub { $class }
						, 'itemsel'   => sub { $sel }
						, 'varvalue'  => sub { $val }
						)
					);
	}
	return ($menuex);
}


=head2 C<varbtnaction ($templ, $who)>

Function C<varbtnaction> is a "$variable" substitution function.
It returns a string suitable for use in the C< action > attribute
of a C<< E<lt>formE<gt> >> tag.

=over

=item 1 C<$templ>

a I<string> containing the template (i.e. argument)

=item 1 C<$who>

a I<string> containing the script name

=back

It passes a skeletal reference to sub C<varlink2action> to do the job.
The reference depends on the script.

Though not mentioned in the code, it relies on C<varlink2action>'s
side-effect to set the value of C<$varparam>.

=cut

sub varbtnaction {
	my ($templ, $who) = @_;
	my $action;

	if ($who eq 'source' || $who eq 'sourcedir') {
		$action = &fileref("", "", $pathname);
	} elsif ($who eq 'diff') {
		$action = &diffref("", "", $pathname);
	} elsif ($who eq 'ident') {
		$action = &idref("", "", $identifier);
	} elsif ($who eq 'search') {
		$action =	"href=\"$config->{virtroot}/search"
						. &urlargs(&nonvarargs())
						. "\">";
	}
	$action =~ m!href="(.*?)(\?|">)!;	# extract href target as action
	return $1;
}


=head2 C<varexpand ($templ, $who)>

Function C<varexpand> is a "$function" substitution function.
It returns an HTML string which is the concatenation of its
expanded argument applied to all configuration variables
(those defined in the C<'variables'> configuration parameter).

=over

=item 1 C<$templ>

a I<string> containing the template (i.e. argument)

=item 1 C<$who>

a I<string> containing the script name

=back

=head3 Algorithm

All variables are considered one after the other and template
expansion is requested through C<expandtemplate> with adequate
replacement rules for the properties.

Some variables may be "conditional". They then have a C<'when'>
attribute which value is a boolean expression. If the expression
evaluates I<true>, the block will be expanded for this variable;
otherwise, the variable is skipped.

The expression is most useful to display variables only when
others have a given value.

The result is the concatenation of the repeated expansion.

=cut

sub varexpand {
	my ($templ, $who) = @_;
	my $varex = '';
	my $var;

	foreach $var ($config->allvariables) {
		if	(!exists($config->{'variables'}{$var}{'when'})
			|| eval($config->varexpand($config->{'variables'}{$var}{'when'}))
			) {
		$varex .= expandtemplate
					( $templ
					,	( 'varname'  => sub { $config->vardescription($var) }
						, 'varid'    => sub { return $var }
						, 'varvalue' => sub { $config->variable($var) }
						, 'varlinks' => sub { varlinks(@_, $who, $var) }
						, 'varmenu'  => sub { varmenuexpand(@_, $who, $var) }
						, 'varbtnaction'=> \&varbtnaction
						)
					);
		}
	}
	return ($varex);
}


=head2 C<devinfo ($templ)>

Function C<dotdoturl> is a "$variable" substitution function.
It returns a string giving information about the LXR modules.

This is a developer debugging substitution. It is not meaningful
for the average user.

=over

=item 1 C<$templ>

a I<string> containing the template

=over

=item

I<< Presently, the template is equal to C<undef>, which is the
template value for a variable substitution request. >

=comment (POD bug?) See previous =comment about >/>>.

=back

=back

=cut

sub devinfo {
	my ($templ) = @_;
	my (@mods, $mod, $path);
	my %mods = ('main' => $0, %INC);

	while (($mod, $path) = each %mods) {
		$mod  =~ s/.pm$//;
		$mod  =~ s!/!::!g;
		$path =~ s!/+!/!g;

		no strict 'refs';
		next unless ${ $mod . '::CVSID' };

		push(@mods, [ ${ $mod . '::CVSID' }, $path, (stat($path))[9] ]);
	}

	return join	( ''
				, map { expandtemplate
						( $templ
						,	( 'moduleid' => sub { $$_[0] }
							, 'modpath'  => sub { $$_[1] }
							, 'modtime'  => sub { scalar(localtime($$_[2])) }
							)
						);
					} sort {$$b[2] <=> $$a[2]} @mods
				);
}


=head2 C<atticlink ($templ)>

Function C<atticlink> is a "$variable" substitution function.
It returns an HTML-string containing an C<< E<lt>AE<gt> >> link to
display/hide CVS files in the "attic" directory.

=over

=item 1 C<$templ>

a I<string> containing the template

=over

=item

I<< Presently, the template is equal to C<undef>, which is the
template value for a variable substitution request. >

=comment (POD bug?) See previous =comment about >/>>.

=back

=back

=cut

sub atticlink {

# This is meaningful only if files lie in a CVS repository
# and the current page is related to some file activity
# (i.e. displaying a directory or a source file)
	return "&nbsp;" if !$files->isa("LXR::Files::CVS");
	return "&nbsp;" if $ENV{'SCRIPT_NAME'} !~ m|/source$|;
# Now build the opposite of the current state
	if ($HTTP->{'param'}->{'_showattic'}) {
		return ("<a class='modes' href=\"$config->{virtroot}/source"
			  . $pathname
			  . &urlargs("_showattic=0")
			  . "\">Hide attic files</a>");
	} else {
		return ("<a class='modes' href=\"$config->{virtroot}/source"
			  . $pathname
			  . &urlargs("_showattic=1")
			  . "\">Show attic files</a>");
	}
}


=head2 C<makeheader ($who)>

Function C<makeheader> outputs the HTML sequence for the top part
of the page (a header) so that all pages have a similar appearance.
It uses a template whose name is derived from the scriptname.

=over

=item 1 C<$who>

a I<string> containing the script name

=back

In case the template is not found, an internal elementary template
is generated to display something.
An error is also logged for the administrator.

=cut

sub makeheader {
	my $who = shift;
	my $tmplname;
	my $template;

	$tmplname = $who . "head";
	unless	($who ne "sourcedir" || exists $config->{'sourcedirhead'}) {
		$tmplname = "sourcehead";
	}
	unless (exists $config->{$tmplname}) {
		$tmplname = "htmlhead";
	}

	$template = gettemplate
					( $tmplname
					, "<html><body>\n<hr>\n"
					, "<hr>\n<p>Trying to display \$pathname</p>\n"
					);

	print(
		expandtemplate
		(	$template
		,	( # --for <head> section--
				'title'      => sub { titleexpand(@_, $who) }
			,	'baseurl'    => sub { baseurl(@_) }
			,	'encoding'   => sub { $config->{'encoding'} }
			,	'stylesheet' => \&stylesheet
			,	'alternatestyle' => sub { altstyleexpand(@_, $who) }
			  # --header decoration--
			,	'caption'    => sub { captionexpand(@_, $who) }
			,	'banner'     => sub { bannerexpand(@_, $who) }
			,	'pathname'   => sub { $pathname }
			,	'atticlink'  => \&atticlink
			,	'LXRversion' => sub { $LXRversion::LXRversion }
			  # --modes buttons & links--
			,	'modes'      => sub { modeexpand(@_, $who) }
			  # --other trees--
			,	'forest'     => sub { forestexpand(@_, $who) }
			  # --variables buttons & links--
			,	'variables'  => sub { varexpand(@_, $who) }
			,	'varbtnaction' => sub { varbtnaction(@_, $who) }
			,	'urlargs'    => sub { urlexpand(@_, $who) }
			  # --various URLs, useless probably--
			,	'dotdoturl'  => \&dotdoturl
			,	'thisurl'    => \&thisurl
			  # --for developers only--
			,	'devinfo'    => \&devinfo
			)
		)
	);
}


=head2 C<makefooter ($who)>

Function C<makefooter> outputs the HTML sequence for the bottom part
of the page (a footer) so that all pages have a similar appearance.
It uses a template whose name is derived from the scriptname.

=over

=item 1 C<$who>

a I<string> containing the script name

=back

In case the template is not found, an internal elementary template
is generated to display something.
An error is also logged for the administrator.

=cut

sub makefooter {
	my $who = shift;
	my $tmplname;
	my $template;

	$tmplname = $who . "tail";
	unless ($who ne "sourcedir" || exists $config->{'sourcedirtail'}) {
		$tmplname = "sourcetail";
	}
	unless (exists $config->{$tmplname}) {
		$tmplname = "htmltail";
	}

	$template = gettemplate
					( $tmplname
					, "<hr>\n"
					, "\n<hr>\n</body></html>\n"
					);

	print(
		expandtemplate
		(	$template
		,	( # --decoration--
				'caption'    => sub { captionexpand(@_, $who) }
			,	'banner'     => sub { bannerexpand(@_, $who) }
			,	'pathname'   => sub { $pathname }
			,	'LXRversion' => sub { $LXRversion::LXRversion }
			  # --modes buttons & links--
			,	'modes'      => sub { modeexpand(@_, $who) }
			  # --variables buttons & links--
			,	'variables'  => sub { varexpand(@_, $who) }
			,	'varbtnaction' => sub { varbtnaction(@_, $who) }
			,	'urlargs'    => sub { urlexpand(@_, $who) }
			  # --various URLs, useless probably--
			,	'dotdoturl'  => \&dotdoturl
			,	'thisurl'    => \&thisurl
			  # --for developers only--
			,	'devinfo'    => \&devinfo
			)
		)
	);
}


=head2 C<makeerrorpage ($who)>

Function C<makeerrorpage> outputs an HTML error page when an
incorrect URL has been submitted: no corresponding source-tree
could be found in the configuration.
It is primarily aimed at giving feedback to the user.

=over

=item 1 C<$who>

a I<string> containing the template name

=back

In case the template is not found, an internal elementary template
is generated to display something.

No assumption is made about the existence of other templates,
e.g. header or footer, since they can be defined merely in the
tree section without being defined in the global section.
Consequently, there is no call to makeheader or makefooter.

=cut

sub makeerrorpage {
	my $who = shift;
	my $tmplname;
	my $template;

	$template = gettemplate
					( $who
					, "<html><body><hr>\n"
 					,  "<hr>\n"
						. "<h1 style='text-align:center'>Unrecoverable Error</h1>\n"
						. "<p>Source-tree \$tree unknown</p>\n"
						. "</body></html>\n"
					);

# Emit a simple HTTP header
	# print("Content-Type: text/html; charset=iso-8859-1\n");
	print("Cache-Control: no-cache, must-revalidate\n");
	print("\n");

	print(
		expandtemplate
		(	$template
		,	( 'target' =>  sub { targetexpand(@_, $who) }
			, 'stylesheet' => \&stylesheet
			, 'LXRversion' => sub { $LXRversion::LXRversion }
			)
		)
	);
	$config = undef;
	$files  = undef;
	$index  = undef;
}

1;
