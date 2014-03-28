# -*- tab-width: 4 -*- mode: perl -*-
###############################################
#
# $Id: Local.pm,v 1.3 2013/09/24 08:54:19 ajlittoz Exp $
#
# Local.pm -- Subroutines that need to be customized for each installation
#
#	Dawn Endico <dawn@cannibal.mi.org>

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

######################################################################
# This package is for placing subroutines that are likely to need
# to be customized for each installation. In particular, the file
# and directory description snarfing mechanism is likely to be
# different for each project.

package Local;

$CVSID = '$Id: Local.pm,v 1.3 2013/09/24 08:54:19 ajlittoz Exp $ ';

use strict;

require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(&filedesc &dirdesc);

use LXR::Common;
use LXR::Markup;

# dme: Create descriptions for a file in a directory listing
# If no description, return the string "\&nbsp\;" to keep the
# table looking pretty.
#
# In mozilla search the beginning of a source file for a short
# description. Not all files have them and the ones that do use
# many different formats. Try to find as many of these without
# printing gobbeldygook or something silly like a file name or a date.
#
# Read in the beginning of the file into a string. I chose 60 because the
# Berkeley copyright notice is around 40 lines long so we need a bit more
# than this.
#
# Its common for file descriptions to be delimited by the file name or
# the word "Description" which preceeds the description. Search the entire
# string for these. Sometimes they're put in odd places such as inside
# the copyright notice or after the code begins. The file name should be
# followed by a colon or some pattern of dashes.
#
# If no such description is found then use the contents of the "first"
# comment as the description. First, strip off the copyright notice plus
# anything before it. Remove rcs comments. Search for the first bit of
# code (usually #include) and remove it plus anything after it. In what's
# left, find the contents of the first comment, and get the first paragraph.
# If that's too long, use only the first sentence up to a period. If that's
# still too long then we probably have a list or something that will look
# strange if we print it out so give up and return null.
#
# Yes, this is a lot of trouble to go through but its easier than getting
# people to use the same format and re-writing thousands of comments. Not
# everything printed will really be a summary of the file, but still the
# signal/noise ratio seems pretty high.
#
# Yea, though I walk through the valley of the shadow of pattern
# matching, I shall fear no regex.
#
# ajl 13-07-09: name changed from fdescexpand to filedesc
# to better mirror dirdesc and emphasize the parallel semantics.
sub filedesc {
	my ($filename, $dir, $releaseid) = @_;
	my $fh;
	my $linecount = 0;
	my $copy = '';
	my $desc = '';
	my $maxlines = 40;    #only look at the beginning of the file

	#ignore files that aren't source code
	if	(	(substr($filename, -2) ne '.c')
		&&	(substr($filename, -2) ne '.h')
		&&	(substr($filename, -3) ne '.cc')
		&&	(substr($filename, -3) ne '.cp')
		&&	(substr($filename, -4) ne '.cpp')
		&&	(substr($filename, -5) ne '.java')
		) {
	return ('&nbsp;');
	}

	if ($fh = $files->getfilehandle($dir . $filename, $releaseid)) {
		while (<$fh>) {
			$desc = $desc . $_;
			if ($linecount++ > 60) {
				last;
			}
		}
		close($fh);
	}

	# sanity check: if there's no description then stop
	if (!($desc =~ m/\w/)) {
		return ('&nbsp;');
	}

	# if a java file, only consider class-level javadoc comments
	if (substr($filename, -5) eq '.java') {

		# last /** ... */ before 'public class' or 'public interface'

		# find declaration
		$desc =~ m/public\s+((abstract|static|final|strictfp)\s+)*(class|interface)/;
		my $declPos = pos $desc;
		return '&nbsp;' if !$declPos;

		# last comment start before declaration
		pos $desc = 0;
		my $commentStart = -1;
		while ($desc =~ m#/\*\*#g) {
			last if $declPos < pos $desc;
			$commentStart = pos $desc;
		}
		return '&nbsp;' if $commentStart == -1;

		# find comment end, and extract
		pos $desc = $commentStart;
		$desc =~ m#\*/#g;
		my $commentEnd = pos $desc;
		$desc = substr	( $desc
						, $commentStart + 3
						, $commentEnd - $commentStart - 5
						);
		return '&nbsp;' if !$desc;

		# strip off any leading * s
		$desc =~ s/^\s*\*\s?//mg;

		# Strip off @parameter lines
		$desc =~ s/^\s*@\w+.*$//mg;

		# strip html tags (probably a way to do this all in one, but it's beyond my skill)
		$desc =~ s#<[/\w]+(\s*\w+="[\w\s]*"\s*)*>##g;    # double quoted attributes
		$desc =~ s#<[/\w]+(\s*\w+='[\w\s]*'\s*)*>##g;    # single quoted attributes
		$desc =~ s#<[/\w]+(\s*\w+=[\w]*\s*)*>##g;        # no quotes on attributes

		# strip off some CVS keyword lines
		foreach my $keyword ('Workfile', 'Revision', 'Modtime', 'Author', 'Id', 'Date', 'Source',
			'RCSfile') {
			$desc =~ s/^\s*\$$keyword[\$:].*$//mg;
		}

	}

	# save a copy for later
	$copy = $desc;

	# Look for well behaved <filename><seperator> formatted
	# descriptions before we go to the trouble of looking for
	# one in the first comment. The whitespace between the
	# delimeter and the description may include a newline.
	if	(  ($desc =~ s/(?:.*?$filename\s*?- ?-*\s*)([^\n]*)(?:.*)/$1/sgi)
		|| ($desc =~ s/(?:.*?$filename\s*?:\s*)([^\n]*)(?:.*)/$1/sgi)
		|| ($desc =~ s/(?:.*?Description:\s*)([^\n]*)(?:.*)/$1/sgi)
		) {

		# if the description is non-empty then clean it up and return it
		if ($desc =~ m/\w/) {

			#strip trailing asterisks and "*/"
			$desc =~ s#\*/?\s*$##;
			$desc =~ s#^[^\S]*\**[^\S]*#\n#gs;

			# Strip beginning and trailing whitespace
			$desc =~ s/^\s+//;
			$desc =~ s/\s+$//;

			# Strip junk from the beginning
			$desc =~ s#[^\w]*##ms;

			#htmlify the comments making links to symbols and files
			$desc = markupstring($desc, $dir);
			return ($desc);
		}
	}

	# if java and the <filename><seperator> check above didn't work, just dump the whole javadoc
	if (substr($filename, -5) eq '.java') {
		return $desc;
	}

	# we didn't find any well behaved descriptions above so start over
	# and look for one in the first comment
	$desc = $copy;

	# Strip off code from the end, starting at the first cpp directive
	$desc =~ s/\n#.*//s;

	# Strip off code from the end, starting at typedef
	$desc =~ s/\n\s*typedef.*//s;

	# Strip off license
	$desc =~ s#(?:/\*.*license.*?\*/)(.*)#$1#is;

	# Strip off copyright notice
	$desc =~ s#(?:/\*.*copyright.*?\*/)(.*)#$1#is;

	# Strip off emacs line
	$desc =~ s#(/\*.*tab-width.*?\*/)(.*)#$2#isg;

	# excise rcs crud
	$desc =~ s#Id: $filename.*?Exp \$##g;

	# Yuck, nuke these silly comments in js/jsj /* ** */
	$desc =~ s#\n\s*/\*+[\s\*]+\*/\n#\n#sg;

	# Don't bother to continue if there aren't any comments here
	if (-1 == index($desc, '/*')) {
		return ('&nbsp;');
	}

	# Remove lines generated by jmc
	$desc =~ s#\n.*?Source date:.*\n#\n#;
	$desc =~ s#\n.*?Generated by jmc.*\n#\n#;

	# Extract the first comment
	$desc =~ s#(?:.*?/\*+)(.*?)(?:(?:\*+/.*)|(?:$))#$1#s;

	# Strip silly borders
	$desc =~ s#\n\s*[\*\=\-\s]+#\n#sg;

	# Strip beginning and trailing whitespace
	$desc =~ s/^\s+//;
	$desc =~ s/\s+$//;

	# Strip out file name
	$desc =~ s#$filename##i;

	# Strip By line
	$desc =~ s#By [^\n]*##;

	# Strip out dates
	$desc =~ s#\d{1,2}/\d{1,2}/\d\d\d\d##;
	$desc =~ s#\d{1,2}/\d{1,2}/\d\d##;
	$desc =~ s#\d{1,2} \w\w\w \d\d\d\d##;

	# Strip junk from the beginning
	$desc =~ s#[^\w]*##;

	# Extract the first paragraph
	$desc =~ s#(\n\s*?\n.*)##s;

	# If the description is too long then just use the first sentence
	# this will fail if no period was used.
	if (length($desc) > 200) {
		$desc =~ s#([^\.]+\.)\s.*#$1#s;
	}

	# If the description is still too long then assume it will look
	# like gobbeldygook and give up
	if (length($desc) > 200) {
		return ('&nbsp;');
	}

	# htmlify the comments, making links to symbols and files
	$desc = markupstring($desc, $dir);

	if ($desc) {
		return ("<p>$desc</p>");
	} else {
		return ('&nbsp;');
	}
}

# dme: Print a descriptive blurb in directory listings between
# the document heading and the table containing the actual listing.
#
# In Mozilla, if the directory has a README file look in it for lines
# like the ones used in source code: "directoryname --- A short description"
#
# For Mozilla, we extract this information from the README file if
# it exists. If the file is short then just print the whole thing.
# For longer files print the first paragraph or so. As much as
# possible make this work for randomly formatted files rather than
# inventing strict rules which create gobbeldygook when they're broken.
sub dirdesc {
	my ($path, $releaseid) = @_;
	my $readh;
	if ($readh = $files->getfilehandle($path . 'README.txt', $releaseid)) {
		return descreadme($path, 'README.txt', $readh);
	}
	if ($readh = $files->getfilehandle($path . 'README', $releaseid)) {
		return descreadme($path, 'README', $readh);
	}
	if ($readh = $files->getfilehandle($path . 'README.html', $releaseid)) {
		return descreadmehtml($path, 'README.html', $readh);
	}
	return '&nbsp;';
}

sub descreadmehtml {
	my ($dir, $file, $desc) = @_;

	my $string = '';

	    undef $/;
	$string = <$desc>;
	    $/ = "\n";
	close($desc);

	# if the README is 0 length then give up
	if (!$string) {
		return '&nbsp;';
	}

	# check if there's a short desc nested inside the long desc. If not, do
	# a non-greedy search for a long desc. assume there are no other stray
	# spans within the description.
	my $long;
	if ($string =~
		m/<span class=["']?lxrlongdesc['"]?>(.*?<span class=["']?lxrshortdesc['"]?>.*?<\/span>.*?)<\/span>/is
	  ) {
		$long = $1;
		if ($long !~ m/<span.*?\<span/is) {
			return	( "<div class='desctext'>$long</div>\n<p>\nSEE ALSO: "
					. fileref($file, '', $dir . $file)
					. "</p>\n"
					);
		}
	} elsif ($string =~ /<span class=["']?lxrlongdesc['"]?>(.*?)<\/span>/is) {
		$long = $1;
		if ($long !~ m/\<span/is) {
			return	( "<div class='desctext lxrlongdesc'>$long</div>\n<p>\nSEE ALSO: "
					. fileref($file, '', $dir . $file)
					. "</p>\n"
					);
		}
	}
	return '&nbsp;';
}

sub descreadme {
	my ($dir, $file, $desc) = @_;

	my $string = '';

	#    $string =~ s#(</?([^>^\s]+[^>]*)>.*$)#($2~/B|A|IMG|FONT|BR|EM|I|TT/i)?$1:""#sg;
	my $n;
	my $count;
	my $temp;

	my $maxlines = 20;    # If file is less than this then just print it all
	my $minlines = 5;     # Too small. Go back and add another paragraph.
	my $chopto   = 10;    # Truncate long READMEs to this length

	    undef $/;
	$string = <$desc>;
	    $/ = "\n";
	close($desc);

	# if the README is 0 length then give up
	if (!$string) {
		return '&nbsp;';
	}

	# strip the emacs tab line
	$string =~ s/.*tab-width:[ \t]*([0-9]+).*\n//;

	# strip the npl
	$string =~ s/.*The contents of this .* All Rights.*Reserved\.//s;

	# strip the short description from the beginning
	$string =~ s/.*$file\s+--- .*//;

	# strip away junk
	$string =~ s/#+\s*\n/\n/;
	$string =~ s/---+\s*\n/\n/g;
	$string =~ s/===+\s*\n/\n/g;

	# strip blank lines at beginning and end of file.
	$string =~ s/^\s*\n//gs;
	$string =~ s/\s*\n$//gs;
	chomp($string);
	$_     = $string;
	$count = tr/\n//;

	# If the file is small there's not much use splitting it up.
	# Just print it all
	if ($count <= $maxlines) {
		$string = markupstring($string, $dir);
		$string = convertwhitespace($string);
		return	"<div class='desctext'><p class='lxrdesc'>\n"
				. $string
				. "\n</p></div>";
	} else {

		# grab the first n paragraphs, with n decreasing until the
		# string is 10 lines or shorter or until we're down to
		# one paragraph.
		$n    = 6;
		$temp = $string;
		while (($count > $chopto) && ($n-- > 1)) {
			$string =~ s/^((?:(?:[\S\t ]*?\n)+?[\t ]*\n){$n}?)(.*)/$1/s;
			$_ = $string;
			$string =~ s/\s*\n$//gs;
			$count = tr/\n//;
		}

		# if we have too few lines then back up and grab another paragraph
		$_     = $string;
		$count = tr/\n//;
		if ($count < $minlines) {
			$n = $n + 1;
			$temp =~ s/^((?:(?:[\S\t ]*?\n)+?[\t ]*\n){$n}?)(.*)/$1/s;
			$string = $temp;
		}

		# if we have more than $maxlines then truncate to $chopto
		# and add an elipsis.
		if ($count > $maxlines) {
			$string =~ s/^((?:[\S \t]*\n){$chopto}?)(.*)/$1/s;
			chomp($string);
			$string = $string . "\n...";
		}

		$string = markupstring($string, $dir);

		# since not all of the README is displayed here,
		# add a link to it.
		chomp($string);
		if (-1 != index($string, 'SEE ALSO')) {
			$string = $string . ', ';
		} else {
			$string = $string . "</p>\n\n<p>SEE ALSO: ";
		}
		$string =~ s|SEE ALSO|</p>\n<p>SEE ALSO|;
		$string .= fileref($file, '', $dir . $file);

		$string = convertwhitespace($string). "\n\n";

		# strip blank lines at beginning and end of file again
		$string =~ s/^\s*\n//gs;
		$string =~ s/\s*\n$//gs;
		chomp($string);

		return	"<div class='desctext'><p class='lxrdesc'>\n"
				. $string
				. "\n</p></div>";
	}
}

# dme: substitute carriage returns and spaces in original text
# for html equivalent so we don't need to use <pre> and can
# use variable width fonts but preserve the formatting
sub convertwhitespace {
	my ($string) = @_;

	# handle ascii bulleted lists
#	$string =~ s/<p>\n\s+o\s/<p>\n\&nbsp\;\&nbsp\;o /sg;
	$string =~ s/\n\s+o\s/\n<br>&nbsp;&nbsp;o /sg;

	#find paragraph breaks and replace by <br>
# 	$string =~ s/\n\s*\n/<br><br>\n/sg;
# 	$string =~ s/(([\S\t ]*?\n)+?)[\t ]*(\n|$)/$1<br>\n/sg;
	$string =~ s/\n\s*\n/\n<br>\n/sg;

	return ($string);
}

1;
