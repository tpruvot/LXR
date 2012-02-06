# -*- tab-width: 4 -*-
###############################################
#
# $Id: Markup.pm,v 1.2 2011/12/26 09:54:25 ajlittoz Exp $
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

This module is the markup engine in charge of highlighting the
syntactic components or otherwise interesting elements of a block.

=cut

package LXR::Markup;

$CVSID = '$Id: Markup.pm,v 1.2 2011/12/26 09:54:25 ajlittoz Exp $';

use strict;

require Exporter;

# use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS
#   $files $index $config $pathname $identifier $releaseid
#   $HTTP $wwwdebug $tmpcounter);

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
# require LXR::Files;
# require LXR::Index;
require LXR::Lang;
use LXR::Common;

# dme: Smaller version of the markupfile function meant for marking up
# the descriptions in source directory listings.
sub markupstring {
	my ($string, $virtp) = @_;

	# Mark special characters so they don't get processed just yet.
	$string =~ s/([\&\<\>])/\0$1/g;

	# Look for identifiers and create links with identifier search query.
	# TODO: Is there a performance problem with this?
	$string =~ s#(^|\s)([a-zA-Z_~][a-zA-Z0-9_]*)\b#
		$1.(is_linkworthy($2) ? &idref($2, "", $2) : $2)#ge;

	# HTMLify the special characters we marked earlier,
	# but not the ones in the recently added xref html links.
	$string =~ s/\0&/&amp;/g;
	$string =~ s/\0</&lt;/g;
	$string =~ s/\0>/&gt;/g;

	# HTMLify email addresses and urls.
	$string =~
	  s#((ftp|http|nntp|snews|news)://(\w|\w\.\w|\~|\-|\/|\#)+(?!\.\b))#<a href=\"$1\">$1</a>#g;

	# htmlify certain addresses which aren't surrounded by <>
	$string =~ s/([\w\-\_]*\@netscape.com)(?!&gt;)/<a href=\"mailto:$1\">$1<\/a>/g;
	$string =~ s/([\w\-\_]*\@mozilla.org)(?!&gt;)/<a href=\"mailto:$1\">$1<\/a>/g;
	$string =~ s/([\w\-\_]*\@gnome.org)(?!&gt;)/<a href=\"mailto:$1\">$1<\/a>/g;
	$string =~ s/([\w\-\_]*\@linux.no)(?!&gt;)/<a href=\"mailto:$1\">$1<\/a>/g;
	$string =~ s/([\w\-\_]*\@sourceforge.net)(?!&gt;)/<a href=\"mailto:$1\">$1<\/a>/g;
	$string =~ s/([\w\-\_]*\@sf.net)(?!&gt;)/<a href=\"mailto:$1\">$1<\/a>/g;
	$string =~ s/(&lt;)(.*@.*)(&gt;)/$1<a href=\"mailto:$2\">$2<\/a>$3/g;

	# HTMLify file names, assuming file is in the current directory.
	$string =~
	  s#\b(([\w\-_\/]+\.(c|h|cc|cp|hpp|cpp|java))|README)\b#{fileref($1, '', $virtp . $1);}#ge;

	return ($string);
}

# dme: Return true if string is in the identifier db and it seems like its
# use in the sentence is as an identifier and its not just some word that
# happens to have been used as a variable name somewhere. We don't want
# words like "of", "to" and "a" to get links. The string must be long
# enough, and  either contain "_" or if some letter besides the first
# is capitalized
sub is_linkworthy {
	my ($string) = @_;

	if (
		$string =~ /....../
		&& ($string =~ /_/ || $string =~ /.[A-Z]/)
		&& $string !~ /README/

		#		&& defined($xref{$string}) FIXME
	  )
	{
		return (1);
	} else {
		return (0);
	}
}

sub markspecials {
	$_[0] =~ s/([\&\<\>])/\0$1/g;
}

sub htmlquote {
	$_[0] =~ s/\0&/&amp;/g;
	$_[0] =~ s/\0</&lt;/g;
	$_[0] =~ s/\0>/&gt;/g;
}

sub freetextmarkup {
	$_[0] =~ s{((f|ht)tp://[^\s<>\0]*[^\s<>\0.])}
			  {<a class='offshore' href="$1">$1</a>}g;
	$_[0] =~ s{(\0<([^\s<>\0]+@[^\s<>\0]+)\0>)}
			  {<a class='offshore' href="mailto:$2">$1</a>}g;
}

sub markupfile {

	#_PH_ supress block is here to avoid the <pre> tag output
	#while called from diff
	my ($fileh, $outfun) = @_;
	my ($dir) = $pathname =~ m|^(.*/)|;
	my $graphic = $config->graphicfile;
# $files->fileversion($pathname, $releaseid);

	# Don't keep href=... in anchor definition
	&fileref(1, "fline", $pathname, 1) =~ m/^(<a.*?)href.*\#(\d+)(\">)\d+(<\/a>)$/;
	my @ltag;
	$ltag[0] = $1 . 'name="';
	my $line = $2;
	$ltag[1] = $3;
	$ltag[2] = $4 . " ";

	# As an optimisation, the skeleton of the <A> link marking for an
	# identifier will be cached in the $lang object.
	# To guard against any modification of the <A> link structure by
	# sub idref, a very specific (and improbable) identifier is used.
	# This allows to make no assumption on idref result.
	my $itagtarget = "!!!";
	my @itag = &idref("$itagtarget", "fid", $itagtarget) =~ /^(.*)$itagtarget(.*)$itagtarget(.*)$/;
	my $lang = new LXR::Lang($pathname, $releaseid, @itag);

	# A source code file
	if ($lang) {
		my $language = $lang->language;    # To get back to the key to lookup the tabwidth.
		&LXR::SimpleParse::init($fileh, $config->filetype->{$language}[3], $lang->parsespec);

		my ($btype, $frag) = &LXR::SimpleParse::nextfrag;

		&$outfun(join($line++, @ltag)) if defined($frag);

		while (defined($frag)) {
			&markspecials($frag);

			if (not defined($btype) ) {
				$btype = '';
			}

			if ($btype eq 'comment') {

				# Comment
				# Convert mail adresses to mailto:
				&freetextmarkup($frag);
				$lang->processcomment(\$frag);
			} elsif ($btype eq 'string') {

				# String
				$frag = "<span class='string'>$frag</span>";
			} elsif ($btype eq 'include') {

				# Include directive
				$lang->processinclude(\$frag, $dir);
			} else {

				# Code
				$lang->processcode(\$frag);
			}

			&htmlquote($frag);
			my $ofrag = $frag;

			($btype, $frag) = &LXR::SimpleParse::nextfrag;

			$ofrag =~ s/\n$// unless defined($frag);
			$ofrag =~ s/\n/"\n".join($line++, @ltag)/ge;

			&$outfun($ofrag);
		}

	} 
	elsif ($pathname =~ /\.$graphic$/)
	{
		&$outfun("<ul><table><tr><th valign=\"center\"><b>Image: </b></th></tr>\n");
		&$outfun("<tr><td>");
		&$outfun("<img src=\""
			  . $config->{'sourceaccess'}
			  . "/" . $config->variable('v')
			  . $pathname
			  . "\" border=\"0\""
			  . " alt=\"$pathname cannot be displayed from this browser\">\n");
		&$outfun("</td></tr></table></ul>");
	}
	elsif ($pathname =~ m|/CREDITS$|) {
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
		if (   !/^\#!/
			&& !/-\*-.*-\*-/i
			&& (length($_) > 132 || /[\000-\010\013\014\016-\037\200-�]/))
		{

			# We postulate that it's a binary file.
			&$outfun("<ul><b>Binary File: ");

			# jwz: URL-quote any special characters.
			my $uname = $pathname;
			$uname =~ s|([^-a-zA-Z0-9.\@/_\r\n])|sprintf("%%%02X", ord($1))|ge;

			&$outfun("<a href=\"$config->{virtroot}/source" . $uname . &urlargs("_raw=1") . "\">");
			&$outfun("$pathname</a></b>");
			&$outfun("</ul>");

		} else {

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
