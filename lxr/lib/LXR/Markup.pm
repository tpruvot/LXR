# -*- tab-width: 4 -*-
###############################################
#
# $Id: Markup.pm,v 1.10 2013/11/08 08:38:19 ajlittoz Exp $
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

=head1 Markup module

This module is the markup engine in charge of highlighting the
syntactic components or otherwise interesting elements of a block.

=cut

package LXR::Markup;

$CVSID = '$Id: Markup.pm,v 1.10 2013/11/08 08:38:19 ajlittoz Exp $';

use strict;

require Exporter;

our @ISA = qw(Exporter);

our @EXPORT = qw(
	&markupstring
	&freetextmarkup
	&markupfile
);
# our @EXPORT_OK = qw();

require Local;
require LXR::SimpleParse;
require LXR::Config;
require LXR::Lang;
use LXR::Common;


=head2 C<markupstring ($string, $virtp)>

Function C<markupstring> returns $string after marking up some items
deemed "interesting" (e-mail addresses, URLs, files, identifiers, ...).

=over

=item 1 C<$string>

a I<string> to mark up

=item 1 C<$virtp>

a I<string> containing the HTML-path for the directory of files

It is used to build a link to files, supposing they are located in this
directory

=back

This is a smaller version of sub C<markupfile> meant for marking up the
descriptions in source directory listings (see Local.pm).

=cut

sub markupstring {
	my ($string, $virtp) = @_;

	# Mark special characters so they don't get processed just yet.
	$string =~ s/([\&\<\>])/\0$1/g;

	# Look for identifiers and create links with identifier search query.
	# TODO: Is there a performance problem with this?
	$string =~ s/(^|\s)([a-zA-Z_~][a-zA-Z0-9_]*)\b/
		$1.	( is_linkworthy($2) && $index->issymbol($2, $releaseid)
			? &idref($2, '', $2)
			: $2
			)/ge;

	# HTMLify the special characters we marked earlier,
	# but not the ones in the recently added xref html links.
	$string =~ s/\0&/&amp;/g;
	$string =~ s/\0</&lt;/g;
	$string =~ s/\0>/&gt;/g;

	# HTMLify email addresses and urls.
	$string =~ s{((ftp|http|nntp|snews|news)://(\w|\w\.\w|\~|\-|\/|\#)+(?!\.\b))}
				{<a href=\"$1\">$1</a>}g;

	# htmlify certain addresses which aren't surrounded by <>
	$string =~ s/([\w\-\_]*\@netscape.com)(?!&gt;)/<a class='offshore' href=\"mailto:$1\">$1<\/a>/g;
	$string =~ s/([\w\-\_]*\@mozilla.org)(?!&gt;)/<a class='offshore' href=\"mailto:$1\">$1<\/a>/g;
	$string =~ s/([\w\-\_]*\@gnome.org)(?!&gt;)/<a class='offshore' href=\"mailto:$1\">$1<\/a>/g;
	$string =~ s/([\w\-\_]*\@linux.no)(?!&gt;)/<a class='offshore' href=\"mailto:$1\">$1<\/a>/g;
	$string =~ s/([\w\-\_]*\@sourceforge.net)(?!&gt;)/<a class='offshore' href=\"mailto:$1\">$1<\/a>/g;
	$string =~ s/([\w\-\_]*\@sf.net)(?!&gt;)/<a class='offshore' href=\"mailto:$1\">$1<\/a>/g;
	$string =~ s/(&lt;)(.*@.*)(&gt;)/$1<a class='offshore' href=\"mailto:$2\">$2<\/a>$3/g;

	# HTMLify file names, assuming file is in the directory defined by $virtp.
	$string =~ s{\b([\w\-_\/]+\.\w{1,5}|README)\b}
				{fileref($1, '', $virtp . $1);}ge;

	return ($string);
}


=head2 C<is_linkworthy ($string)>

Function C<is_linkworthy> returns true if $string is in the identifier DB
and seems to be used as an identifier (not just some word that happens to
have been used as a variable name somewhere).

=over

=item 1 C<$string>

a I<string> containing the symbol to check

=back

The string must be long enough (to bar words like "of", "to" or "a").
Presently it must be at least 6 characters long.
It looks like an identifier if it contains an underscore ("_") or a capitalized
letter after the first character.

Some common names like README are rejected.

The symbol must also have been entered into the DB.

B<TO DO:>

=over

=item

DB check is not implemented.
It could be through C<index-E<gt>symreferences($string, $releaseid)>
or C<$index-E<gt>symdeclarations($string, $releaseid)>
if we want to consider only declared identifiers.

=back

=cut

sub is_linkworthy {
	my ($string) = @_;

	return	(	5 < length($string)
			&&	(	0 <= index($string, '_')
				||	$string =~ m/^.[a-zA-Z]/
				)
			&&	0 > index($string, 'README')
	#		&&	defined($xref{$string}) FIXME
			);
}


=head2 C<markspecials ($string)>

Function C<markspecials> tags "special" characters in its argument
with a NUL (\0).

=over

=item 1 C<$string>

a I<string> to tag

=back

This sub is called before editing (highlighting) the string argument
so that we can later distinguish between original litteral HTML special
characters and those added as part of HTML tags.

=cut

sub markspecials {
	$_[0] =~ s/([\&\<\>])/\0$1/g;
}


=head2 C<htmlquote ($string)>

Function C<htmlquote> untags "special" characters in its argument
and HTML-quote them.

=over

=item 1 C<$string>

a I<string> to untag

=back

This sub is called as the last step of editing (highlighting) before
emitting the string as HTML stream.
The originally litteral special HTML characters are replaced by their
entity name equivalent.

At the same time, the "start of line" marker added by sub C<nextfrag> is
also removed to revert to the original source text.

=cut

sub htmlquote {
	$_[0] =~ s/\0&/&amp;/g;
	$_[0] =~ s/\0</&lt;/g;
	$_[0] =~ s/\0>/&gt;/g;
}


=head2 C<freetextmarkup ($string)>

Function C<freetextmarkup> creates links in its argument for URLs and e-mail addresses.

=over

=item 1 C<$string>

a I<string> to edit

=back

This sub is intended to create links in comments or otherwise free text.

=cut

sub freetextmarkup {
	$_[0] =~ s{((f|ht)tp://[^\s<>\0]*[^\s<>\0.])}
			  {<a class='offshore' href="$1">$1</a>}g;
	$_[0] =~ s{(\0<([^\s<>\0]+@[^\s<>\0]+)\0>)}
			  {<a class='offshore' href="mailto:$2">$1</a>}g;
}


=head2 C<markupfile ($fileh, $outfun)>

Function C<markupfile> is the edition driver.

=over

=item 1 C<$fileh>

a I<filehandle> for the source file

=item 1 C<$outfun>

a reference to a I<sub> which outputs the HTML stream

=back

This sub calls the parser to split the source file into homogeneous
fragments which are highlighted by various specialized support routines.

Sub C<&outfun> is called to output the HTML stream.
Use of a subroutine allows to do the highlighting with C<markupfile> in
every context (single file display by I<source> or dual file display
by I<diff>).

=cut

sub markupfile {

	my ($fileh, $outfun) = @_;
	my ($dir) = $pathname =~ m|^(.*/)|;
	my $graphic = $config->{'graphicfile'};

	#	Every line is tagged with an <A> anchor so that it can be referenced
	#	and jumped to. The easiest way to create this anchor is to generate
	#	a link by sub fileref. The elements are then extracted and stored in
	#	array @ltag (=line tag):
	#	0: beginning of anchor '<a class=... name="'
	#	1: '">'
	#	2: '</a>'
	#	Later, it only needs to insert line numbers betwwen 0-1 and 1-2 to
	#	have the correct anchor.
	&fileref(1, 'fline', $pathname, 1) =~ m/^(<a.*?)href.*\#(\d+)(\">)\d+(<\/a>)$/;
	my @ltag;
	$ltag[0] = $1 . 'name="';
	my $line = $2;
	$ltag[1] = $3;
	$ltag[2] = $4 . ' ';

	# As an optimisation, the skeleton of the <A> link marking for an
	# identifier will be cached in the $lang object.
	# To guard against any modification of the <A> link structure by
	# sub idref, a very specific (and improbable) identifier is used.
	# This allows to make no assumption on idref result.
	my $itagtarget = '---';
	my @itag = &idref($itagtarget, 'fid', $itagtarget) =~ m/^(.*)$itagtarget(.*)$itagtarget(.*)$/;
	my $lang = LXR::Lang->new($pathname, $releaseid, @itag);

	my ($btype, $frag, $ofrag);
	if ($lang) {
	# Source code file if $lang is defined, meaning a parser has been found
		my $language = $lang->{'ltype'};	# To get back to the key to lookup the tabwidth.
		&LXR::SimpleParse::init($fileh, ${$config->{'filetype'}{$language}}[3], $lang->parsespec);

		($btype, $frag) = &LXR::SimpleParse::nextfrag;

		&$outfun(join($line++, @ltag)) if defined($frag);

		#	Loop until nextfrag returns no more fragments
		while (defined($frag)) {
			$frag =~ s/^(\n*)//;	# remove initial empty lines
			$ofrag = $1;
			&markspecials($frag);	# guard against HTML special characters

			#	Process every fragment according to its category
			if ($btype) {
				if (		'comment'	eq substr($btype, 0, 7)) {
					# Comment
					&freetextmarkup($frag);	# Convert mail adresses to mailto:
					$lang->processcomment(\$frag, $btype);
				} elsif (	'string'	eq substr($btype, 0, 6)) {
					# String
					$lang->processstring(\$frag, $btype);
				} elsif (	'include'	eq $btype) {
					# Include directive
					$lang->processinclude(\$frag, $dir);
				} elsif (	'extra'		eq substr($btype, 0, 5)) {
					# Language specific
					$lang->processextra(\$frag, $btype);
				} else {
					# Unknown category
					# TODO: create a processunknown method
					$lang->processcode(\$frag);
				}
			} else {
				# Code
				$lang->processcode(\$frag);
			}

			&htmlquote($frag);
			$ofrag .= $frag;

			($btype, $frag) = &LXR::SimpleParse::nextfrag;

			#	Prepare for next line if any
			$ofrag =~ s/\n$// unless defined($frag);
			$ofrag =~ s/\n/"\n".join($line++, @ltag)/ge;

			&$outfun($ofrag);
		}

	} elsif ($pathname =~ m/\.($graphic)$/) {
	# Graphic files are detected by their extension
		&$outfun('<b>Image: </b>');
		&$outfun('<img src="'
				. $config->{'sourceaccess'}
				. '/' . $config->variable('v')
				. $pathname
				. '" border="0"'
				. " alt=\"No access to $pathname or browser cannot display this format\">");
	} elsif ($pathname =~ m|/CREDITS$|) {
	# Special case
		while (defined($_ = $fileh->getline)) {
			&LXR::SimpleParse::untabify($_);
			&markspecials($_);
			&htmlquote($_);
			s/^N:\s+(.*)/<strong>$1<\/strong>/gm;
			s/^(E:\s+)(\S+@\S+)/$1<a href=\"mailto:$2\">$2<\/a>/gm;
			s/^(W:\s+)(.*)/$1<a href=\"$2\">$2<\/a>/gm;
			&$outfun(join($line++, @ltag) . $_);
		}
	} else {
		return unless defined($_ = $fileh->getline);

		# If it's not a script or something with an Emacs spec header and
		# the first line is very long or containts control characters...
		if	(	substr($_, 0, 2) ne '#!'
			&&	! m/-\*-.*-\*-/
			&&	(	length($_) > 132
				||	m/[\x00-\x08\x0B\x0C\x0E-\x1F\x80-\x9F]/
				)
			) {
			# We postulate that it's a binary file.
			&$outfun('<ul><b>Binary File: ');
			# jwz: URL-quote any special characters.
			my $uname = $pathname;
			$uname =~ s|([^-a-zA-Z0-9.\@/_\r\n])|sprintf("%%%02X", ord($1))|ge;

			&$outfun	( '<a href="'
						. $config->{'virtroot'}
						. 'source'
						. $uname
						. &urlargs('_raw=1')
						. '">'
						);
			&$outfun("$pathname</a></b>");
			&$outfun('</ul>');

		} else {
		# Unqualified text file, do minimal work
			do {
				&LXR::SimpleParse::untabify($_);
				&markspecials($_);
				&freetextmarkup($_);
				&htmlquote($_);
				&$outfun(join($line++, @ltag) . $_);
			} while (defined($_ = $fileh->getline));

		}
	}
}

1;
