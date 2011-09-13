# -*- tab-width: 4 -*- ###############################################
#
# $Id: Common.pm,v 1.82 2011/06/10 15:48:35 ajlittoz Exp $
#
# FIXME: java doesn't support super() or super.x

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

package LXR::Common;

$CVSID = '$Id: Common.pm,v 1.82 2011/06/10 15:48:35 ajlittoz Exp $ ';

use strict;

require Exporter;

use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS
  $files $index $config $pathname $identifier $releaseid
  $HTTP $wwwdebug $tmpcounter);

@ISA = qw(Exporter);

@EXPORT    = qw($files $index $config &fatal);
@EXPORT_OK = qw($files $index $config $pathname $identifier $releaseid
  $HTTP
  &warning &fatal &abortall &fflush &urlargs &fileref
  &idref &incref &htmlquote &freetextmarkup &markupfile
  &markupstring &httpinit &makeheader &makefooter
  &expandtemplate &httpclean);

%EXPORT_TAGS = ('html' => [@EXPORT_OK]);

require Local;
require LXR::SimpleParse;
require LXR::Config;
require LXR::Files;
require LXR::Index;
require LXR::Lang;
#ajl
#	LXRversion has been stored in an independant file
#	so that changing its number will not mess up CVS Id
#	leading to believe that some bug has been fixed or
#	a feature added
#
require LXRversion;

$wwwdebug = 0;

$tmpcounter = 23;

sub warning {
	my $c = join(", line ", (caller)[ 0, 2 ]);
	print(STDERR "[", scalar(localtime), "] warning: $c: $_[0]\n");
	print("<h4 align=\"center\"><i>** Warning: $_[0]</i></h4>\n") if $wwwdebug;
}

sub fatal {
	my $c = join(", line ", (caller)[ 0, 2 ]);
	print(STDERR "[", scalar(localtime), "] fatal: $c: $_[0]\n");
	print(STDERR '[@INC ', join(" ", @INC), ' $0 ', $0, "\n");
	print(STDERR '$config', join(" ", %$config), "\n") if ref($config) eq "HASH";
	print("<h4 align=\"center\"><i>** Fatal: $_[0]</i></h4>\n") if $wwwdebug;
	exit(1);
}

sub abortall {
	my $c = join(", line ", (caller)[ 0, 2 ]);
	print(STDERR "[", scalar(localtime), "] abortall: $c: $_[0]\n");
	print(
		"Content-Type: text/html; charset=iso-8859-1\n\n",
		"<html>\n<head>\n<title>Abort</title>\n</head>\n",
		"<body><h1>Abort!</h1>\n",
		"<b><i>** Aborting: $_[0]</i></b>\n",
		"</body>\n</html>\n"
	  )
	  if $wwwdebug;
	exit(1);
}

sub fflush {
	$| = 1;
	print('');
}

sub tmpcounter {
	return $tmpcounter++;
}

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

	return ($#args < 0 ? '' : '?' . join(';', @args));
}

sub fileref {
	my ($desc, $css, $path, $line, @args) = @_;

	# jwz: URL-quote any special characters.
	$path =~ s|([^-a-zA-Z0-9.\@/_\r\n])|sprintf("%%%02X", ord($1))|ge;

	if ($line > 0 && length($line) < 3) {
		$line = ('0' x (3 - length($line))) . $line;
	}

	return ("<a class='$css' href=\"$config->{virtroot}/source$path"
		  . &urlargs(@args)
		  . ($line > 0 ? "#$line" : "")
		  . "\"\>$desc</a>");
}

sub diffref {
	my ($desc, $css, $path, $darg) = @_;
	my $dval;

	($darg, $dval) = $darg =~ /(.*?)=(.*)/;
	return ("<a class='$css' href=\"$config->{virtroot}/diff$path"
		  . &urlargs(($darg ? "diffvar=$darg" : ""), ($dval ? "diffval=$dval" : ""))
		  . "\"\>$desc</a>");
}

sub idref {
	my ($desc, $css, $id, @args) = @_;
	return ("<a class='$css' href=\"$config->{virtroot}/ident"
		  . &urlargs(($id ? "i=$id" : ""), @args)
		  . "\"\>$desc</a>");
}

sub incref {
	my ($name, $css, $file, @paths) = @_;
	my ($dir, $path);

	push(@paths, $config->incprefix);

	foreach $dir (@paths) {
		$dir =~ s/\/+$//;
		$path = $config->mappath($dir . "/" . $file);
		return &fileref($name, $css, $path) if $files->isfile($path, $releaseid);

	}

	return $name;
}

sub http_wash {
	my $t = shift;
	if (!defined($t)) {
		return (undef);
	}

	$t =~ s/\%([\da-f][\da-f])/pack("C", hex($1))/gie;

	return ($t);
}

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

	my $line = '001';
	# Don't keep href=... in anchor definition
	my @ltag = &fileref(1, "fline", $pathname, 1) =~ /^(<a.*?)(?:href.*\#)\d+(\">)\d+(<\/a>)$/;
	$ltag[0] .= 'name="';
	$ltag[2] .= " ";

	my @itag = &idref(1, "fid", 1) =~ /^(.*=)1(\">)1(<\/a>)$/;
	my $lang = new LXR::Lang($pathname, $releaseid, @itag);

	# A source code file
	if ($lang) {
		my $language = $lang->language;    # To get back to the key to lookup the tabwidth.
		&LXR::SimpleParse::init($fileh, $config->filetype->{$language}[3], $lang->parsespec);

		my ($btype, $frag) = &LXR::SimpleParse::nextfrag;

		#&$outfun("<pre class=\"file\">\n");
		&$outfun(join($line++, @ltag)) if defined($frag);

		while (defined($frag)) {
			&markspecials($frag);

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

		#&$outfun("</pre>");
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

			# &$outfun("<a name=\"L$.\"><\/a>".$_);
			&$outfun(join($line++, @ltag) . $_);
		}
	} else {
		return unless defined($_ = $fileh->getline);

		# If it's not a script or something with an Emacs spec header and
		# the first line is very long or containts control characters...
		if (   !/^\#!/
			&& !/-\*-.*-\*-/i
			&& (length($_) > 132 || /[\000-\010\013\014\016-\037\200-Ÿ]/))
		{

			# We postulate that it's a binary file.
			&$outfun("<ul><b>Binary File: ");

			# jwz: URL-quote any special characters.
			my $uname = $pathname;
			$uname =~ s|([^-a-zA-Z0-9.\@/_\r\n])|sprintf("%%%02X", ord($1))|ge;

			&$outfun("<a href=\"$config->{virtroot}/source" . $uname . &urlargs("raw=1") . "\">");
			&$outfun("$pathname</a></b>");
			&$outfun("</ul>");

		} else {

			#&$outfun("<pre class=\"file\">\n");
			do {
				&LXR::SimpleParse::untabify($_);
				&markspecials($_);
				&freetextmarkup($_);
				&htmlquote($_);

				#		&$outfun("<a name=\"L$.\"><\/a>".$_);
				&$outfun(join($line++, @ltag) . $_);
			} while (defined($_ = $fileh->getline));

			#&$outfun("</pre>");
		}
	}
}

sub fixpaths {
	my $node = '/' . shift;

	while ($node =~ s|/[^/]+/\.\./|/|g) { }
	$node =~ s|/\.\./|/|g;

	$node .= '/' if $files->isdir($node, $releaseid);
	$node =~ s|//+|/|g;

	return $node;
}

sub printhttp {

	# Print out a Last-Modified date that is the larger of: the
	# underlying file that we are presenting; and the "source" script
	# itself (passed in as an argument to this function.)  If we can't
	# stat either of them, don't print out a L-M header.  (Note that this
	# stats lxr/source but not lxr/lib/LXR/Common.pm.  Oh well, I can
	# live with that I guess...)	-- jwz, 16-Jun-98

	# Made it stat all currently loaded modules.  -- agg.

	# Todo: check lxr.conf.

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

	if ($HTTP->{'param'}->{'raw'}) {

		#FIXME - need more types here
		my %type = (
			'gif'  => 'image/gif',
			'html' => 'text/html'
		);

		if ($pathname =~ /\.([^.]+)$/ && $type{$1}) {
			print("Content-type: ", $type{$1}, "\n");
		} else {
			print("Content-Type: text/plain\n");
		}
	}
	else
	{
		print("Content-Type: text/html; charset=", $config->{'encoding'}, "\n");
	}

	# Close the HTTP header block.
	print("\n");
}

# httpinit - parses and cleans up the URL parameters and sets up the various variables
#            Also prints the HTTP header & sets up the signal handlers
#			This is also where we protect from malicious input
#
# HTTP:
# path_info -
# param		- Array of parameters
# this_url	- The current url
#
sub httpinit {
	$SIG{__WARN__} = \&warning;
	$SIG{__DIE__}  = \&fatal;

	$ENV{'PATH'} = '/bin:/usr/local/bin:/usr/bin:/usr/sbin';

	$HTTP->{'path_info'} = http_wash($ENV{'PATH_INFO'});

	$HTTP->{'path_info'} = clean_path($HTTP->{'path_info'});
	$HTTP->{'this_url'} = 'http://' . $ENV{'SERVER_NAME'};
	$HTTP->{'this_url'} .= ':' . $ENV{'SERVER_PORT'}
	  if $ENV{'SERVER_PORT'} != 80;
	$HTTP->{'this_url'} .= $ENV{'SCRIPT_NAME'} . $ENV{'PATH_INFO'};
	$HTTP->{'this_url'} .= '?' . $ENV{'QUERY_STRING'}
	  if $ENV{'QUERY_STRING'};

	# We don't clean all the parameters here, as some scripts need extended characters
	# e.g. regexp searching
	$HTTP->{'param'} = { map { http_wash($_) } $ENV{'QUERY_STRING'} =~ /([^;&=]+)(?:=([^;&]+)|)/g }
	  if defined $ENV{'QUERY_STRING'};

	# But do clean up these
	$HTTP->{'param'}->{'v'} ||= $HTTP->{'param'}->{'version'};
	$HTTP->{'param'}->{'a'} ||= $HTTP->{'param'}->{'arch'};
	$HTTP->{'param'}->{'i'} ||= $HTTP->{'param'}->{'identifier'};

	$identifier = clean_identifier($HTTP->{'param'}->{'i'});
	# remove the param versions to prevent unclean versions being used
	delete $HTTP->{'param'}->{'i'};
	delete $HTTP->{'param'}->{'identifier'};

	$config     = new LXR::Config($HTTP->{'this_url'});
	if (exists $config->{'configerror'}) {
		makeerrorpage('htmlfatal');
		die "Can't find config for " . $HTTP->{'this_url'};
	}
	$files = new LXR::Files($config->sourceroot, $config->sourceparams);
	die "Can't create Files for " . $config->sourceroot if !defined($files);
	$index = new LXR::Index($config->dbname);
	die "Can't create Index for " . $config->dbname if !defined($index);

	foreach ($config->allvariables) {
		$config->variable($_, $HTTP->{'param'}->{$_}) if $HTTP->{'param'}->{$_};
		delete $HTTP->{'param'}->{$_};
	}

	$HTTP->{'param'}->{'file'} = clean_path($HTTP->{'param'}->{'file'});
	$pathname = fixpaths($HTTP->{'path_info'} || $HTTP->{'param'}->{'file'});

	$releaseid  = clean_release($config->variable('v'));
	$config->variable('v', $releaseid);  # put back into config obj

	printhttp;
}

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

sub clean_identifier {
	# Cleans up the identifier parameter
	# Result should be HTML-safe and a valid identifier in
	# any supported language...
	# Well, not Lisp symbols since they can contain anything
	my $id = shift;

	$id =~ s/[^\w`:.,\-_ ]//g if defined $id;

	return $id;
}

sub clean_path {
	# Cleans up a string to path
	my $path = shift;

	if(defined $path) {
		# First suppress anything after a dodgy character
	    #  Match good chars from start of string, then replace entire string with only good chars
		$path =~ s!(^[\w\s_+\-,\.%\^/\!]+).*!$1!;
		# Clean out /../
		while ($path =~ m!/\.\.?/!) {
			$path =~ s!/\.\.?/!/!g;
		}
	}

	return $path;
}

sub httpclean {
	$config = undef;
	$files  = undef;

	$index->DESTROY();
	$index  = undef;
}

sub expandtemplate {
	my ($templ, %expfunc) = @_;
	my ($expfun, $exppar);

	while ($templ =~ s/(\{[^\{\}]*)\{([^\{\}]*)\}/$1\01$2\02/s) { }

	$templ =~ s/(\$(\w+)(\{([^\}]*)\}|))/{
		if (defined($expfun = $expfunc{$2})) {
			if ($3 eq '') {
				&$expfun(undef);
			}
			else {
				$exppar = $4;
				$exppar =~ s#\01#\{#gs;
				$exppar =~ s#\02#\}#gs;
				&$expfun($exppar);
			}
		}
		else {
			$1;
		}
	}/ges;

	$templ =~ s/\01/\{/gs;
	$templ =~ s/\02/\}/gs;
	return ($templ);
}

# What follows is somewhat less hairy way of expanding nested
# templates than it used to be.  State information is passed via
# function arguments, as God intended.
sub bannerexpand {
	my ($templ, $who) = @_;

	if ($who eq 'source' || $who eq 'sourcedir' || $who eq 'diff') {
		my $fpath = '';
		my $furl  = fileref($config->sourcerootname . '/', "banner", '/');

		foreach ($pathname =~ m|([^/]+/?)|g) {
			$fpath .= $_;

			# ajl: put a zero-width space after each / in the banner
			# so that it's possible for the pathnames to wrap.
			# The <wbr> tag ought to do this, but it is ignored when
			# sizing table cells, so we have to use a real character.
			$furl .= '&#x200B;' . fileref($_, "banner", "/$fpath");
		}
		$furl =~ s|/</a>|</a>/|gi;

		return "<span class=\"banner\">$furl</span>";
	} else {
		return '';
	}
}

sub pathname {
	return $pathname;
}

sub titleexpand {
	my ($templ, $who) = @_;

	if ($who eq 'source' || $who eq 'diff' || $who eq 'sourcedir') {
		return $config->sourcerootname . $pathname;
	} elsif ($who eq 'ident') {
		my $i = $HTTP->{'param'}->{'i'};
		return $config->sourcerootname . ' identifier search' . ($i ? ": $i" : '');
	} elsif ($who eq 'search') {
		my $s = $HTTP->{'param'}->{'string'};
		$s =~ s/</&lt;/g;
		$s =~ s/>/&gt;/g;
		return $config->sourcerootname . ' general search' . ($s ? ": $s" : '');
	}
}

sub thisurl {
	my $url = $HTTP->{'this_url'};

	$url =~ s/([\?\&\;\=])/sprintf('%%%02x',(unpack('c',$1)))/ge;
	return ($url);
}

sub baseurl {
	(my $url = $config->baseurl) =~ s|/*$|/|;

	return $url;
}

sub stylesheet {
	return $config->stylesheet;
}

sub dotdoturl {
	my $url = $config->baseurl;
	$url =~ s@/$@@;
	$url =~ s@/[^/]*$@@;
	return ($url);
}

sub modelink2button
{	my ($ref) = @_;

	$ref =~ s|<a|<form method="get"|;
	$ref =~ s|href|action|;
	if ($ref =~ s|\?|">?|) {
		$ref =~ s|">([^?])|<button type="submit">$1|;
		$ref =~ s|[?&;](\w+)=(.*?)(?=[&;<])|<input type="hidden" name="$1" value="$2">|g;
	}
	else {
		$ref =~ s|">|"><button type="submit">$1|;
	}
	$ref =~ s|</a>|</button></form>|;
	return $ref;
}

# This one isn't too bad either.  We just expand the "modes" template
# by filling in all the relevant values in the nested "modelink"
# template.
sub modeexpand {
	my ($templ, $who) = @_;
	my $modex = '';
	my $ref;
	my @mlist = ();
	my @mblist = ();
	my $mode;
	my $modebtn;

	if ($who eq 'source' || $who eq 'sourcedir')
	{	push(@mlist, "<span class='modes-sel'>source navigation</span>");
		push	( @mblist
				, "<form method='get' class='modes-sel' action=''>"
					. "<button type='submit' disabled>source navigation</button>"
					. "</form>"
				);
	} else
	{	$ref = fileref("source navigation", "modes", $pathname);
		push(@mlist, $ref);
		push(@mblist, modelink2button($ref));
	}

	if ($who eq 'diff')
	{	push(@mlist, "<span class='modes-sel'>diff markup</span>");
		push	( @mblist
				, "<form method='get' class='modes-sel' action=''>"
					. "<button type='submit' disabled>diff markup</button>"
					. "</form>"
				);
	} elsif ($who eq 'source' && $pathname !~ m|/$|)
	{	$ref = diffref("diff markup", "modes", $pathname);
		push(@mlist, $ref);
		push(@mblist, modelink2button($ref));
	}

	if ($who eq 'ident')
	{	push(@mlist, "<span class='modes-sel'>identifier search</span>");
		push	( @mblist
				, "<form method='get' class='modes-sel' action=''>"
					. "<button type='submit' disabled>identifier search</button>"
					. "</form>"
				);
	} else
	{	$ref = idref("identifier search", "modes", "");
		push(@mlist, $ref);
		push(@mblist, modelink2button($ref));
	}

	if ($who eq 'search')
	{	push(@mlist, "<span class='modes-sel'>general search</span>");
		push	( @mblist
				, "<form method='get' class='modes-sel' action=''>"
					. "<button type='submit' disabled>general search</button>"
					. "</form>"
				);
	} else
	{	$ref = "<a class=\"modes\" "
			  . "href=\"$config->{virtroot}/search"
			  . urlargs
			  . "\">general search</a>";
		push(@mlist, $ref);
		push	( @mblist
				, modelink2button($ref)
				);
	}

	foreach $mode (@mlist)
	{ 	$modebtn = shift(@mblist);
		$modex .= expandtemplate	(
					$templ,
					(	'modelink'	=> sub { return $mode }
					,	'modebtn' 	=> sub { return $modebtn }
					)				);
	}

	return ($modex);
}

# This is where it gets a bit tricky.  varexpand expands the
# "variables" template using varname and varlinks, the latter in turn
# expands the nested "varlinks" template using varval.
sub varlinks {
	my ($templ, $who, $var) = @_;
	my $vlex = '';
	my ($val, $oldval);
	my $vallink;

	$oldval = $config->variable($var);
	foreach $val ($config->varrange($var)) {
		if ($val eq $oldval) {
			$vallink = "<span class=\"var-sel\">$val</span>";
		} else {
			if ($who eq 'source' || $who eq 'sourcedir') {
				$vallink = &fileref($val, "varlink", $config->mappath($pathname, "$var=$val"),
					0, "$var=$val");

			} elsif ($who eq 'diff') {
				$vallink = &diffref($val, "varlink", $pathname, "$var=$val");
			} elsif ($who eq 'ident') {
				$vallink = &idref($val, "varlink", $identifier, "$var=$val");
			} elsif ($who eq 'search') {
				$vallink =
				    "<a class=\"varlink\" href=\"$config->{virtroot}/search"
				  . &urlargs("$var=$val", "string=" . $HTTP->{'param'}->{'string'})
				  . "\">$val</a>";
			}
		}

		$vlex .= expandtemplate($templ, ('varvalue' => sub { return $vallink }));

	}
	return ($vlex);
}

sub varmenu {
	my ($var) = @_;
	my $val;
	my $valmenu = '';

	my $oldval = $config->variable($var);
	my $defval = $config->vardefault($var);
	foreach $val ($config->varrange($var)) {
		$valmenu .= "<option class=\"";
		if ($val eq $oldval)
		{	$valmenu .= "var-sel\" selected";
		} else
		{	$valmenu .= "varlink\"";
		}
# TODO Find a way of preventing sending the default value (though harmless)
# 		if ($val eq $defval)
# 		{	$valmenu .= "???";
# 		}
		$valmenu .= ">$val</option>";
	}
	return ($valmenu);
}

my $hidden;
sub varlink2action
{	my ($ref) = @_;
	my $var;
	my $val;

	$hidden = "";
	$ref =~ s|<a.*href=||;
	$ref =~ s|>.*$||;
	$ref =~ s|\?(.*)"$|"|;
	my $param = $1;
	while ($param =~ s/(.*?)=(.*?)([&;]|$)//) {
		$var = $1;
		$val = $2;
		$hidden .= "<input type='hidden' name='"
				. $var
				. "' value='"
				. $val
				. "'>";
	}
	return $ref;
}

sub varaction {
	my ($who) = @_;
	my $val;
	my $valaction;

	if ($who eq 'source' || $who eq 'sourcedir') {
# TODO $varaction is used, but for diffhead, outside the "variables" template.
#		We thus have no idea of the current values of the variables.
#		To get them, we need to wait until the submit button is clicked.
#		Then we could apply mappath. Unhappily, $pathname is not
#		guaranteed to be an 'original' path; it may already have undergone
#		a mappath transformation. It is then not safe to apply a second time.
# 		$valaction = varlink2action(&fileref("$val", ""
# 									, $config->mappath($pathname, "$var=$val")
# 									, 0, "$var=$val")
# 								  );
		$valaction = varlink2action(&fileref("", "", $pathname, 0));
	} elsif ($who eq 'diff') {
		$valaction = varlink2action(&diffref("", "", $pathname));
	} elsif ($who eq 'ident') {
		$valaction = varlink2action(&idref("", "", $identifier));
	} elsif ($who eq 'search') {
		$valaction = varlink2action(
			"\"$config->{virtroot}/search"
		  . &urlargs("string=" . $HTTP->{'param'}->{'string'})
		  . "\""
								);
	}
	return $valaction;
}

sub varexpand {
	my ($templ, $who) = @_;
	my $varex = '';
	my $var;

	foreach $var ($config->allvariables) {
		$varex .= expandtemplate(
			$templ,
			( 'varname'  => sub { $config->vardescription($var) }
			, 'varid'    => sub { return $var }
			, 'varlinks' => sub { varlinks(@_, $who, $var) }
			, 'varmenu'  => sub { varmenu($var) }
			, 'varaction'=> sub { varaction($who) }
			, 'varparam' => sub { $hidden }
			)
		);
	}
	return ($varex);
}

sub devinfo {
	my ($templ) = @_;
	my (@mods, $mod, $path);
	my %mods = ('main' => $0, %INC);

	while (($mod, $path) = each %mods) {
		$mod  =~ s/.pm$//;
		$mod  =~ s|/|::|g;
		$path =~ s|/+|/|g;

		no strict 'refs';
		next unless ${ $mod . '::CVSID' };

		push(@mods, [ ${ $mod . '::CVSID' }, $path, (stat($path))[9] ]);
	}

	return join(
		'',
		map {
			expandtemplate(
				$templ,
				(
					'moduleid' => sub { $$_[0] },
					'modpath'  => sub { $$_[1] },
					'modtime'  => sub { scalar(localtime($$_[2])) }
				)
			);
		  }
		  sort {
			$$b[2] <=> $$a[2]
		  } @mods
	);
}

sub atticlink {
	return "&nbsp;" if !$files->isa("LXR::Files::CVS");
	return "&nbsp;" if $ENV{'SCRIPT_NAME'} !~ m|/source$|;
	if ($HTTP->{'param'}->{'showattic'}) {
		return ("<a class='modes' href=\"$config->{virtroot}/source"
			  . $HTTP->{'path_info'}
			  . &urlargs("showattic=0")
			  . "\">Hide attic files</a>");
	} else {
		return ("<a class='modes' href=\"$config->{virtroot}/source"
			  . $HTTP->{'path_info'}
			  . &urlargs("showattic=1")
			  . "\">Show attic files</a>");
	}
}

sub makeheader {
	my $who = shift;
	my $tmplname;
	my $template = "<html><body>\n<hr>\n";

	$tmplname = $who . "head";

	unless ($who ne "sourcedir" || $config->sourcedirhead) {
		$tmplname = "sourcehead";
	}
	unless ($config->value($tmplname)) {
		$tmplname = "htmlhead";
	}

	if ($config->value($tmplname)) {
		if (open(TEMPL, $config->value($tmplname))) {
			local ($/) = undef;
			$template = <TEMPL>;
			close(TEMPL);
		} else {
			warning("Template " . $config->value($tmplname) . " does not exist in ".`pwd`);
		}
	}

	#CSS checked _PH_
	print(
		expandtemplate(
			$template,
			(	'title'      => sub { titleexpand(@_,  $who) }
			,	'banner'     => sub { bannerexpand(@_, $who) }
			,	'baseurl'    => sub { baseurl(@_) }
			,	'stylesheet' => sub { stylesheet(@_) }
			,	'dotdoturl'  => sub { dotdoturl(@_) }
			,	'thisurl'    => sub { thisurl(@_) }
			,	'pathname'   => sub { pathname(@_) }
			,	'modes'      => sub { modeexpand(@_,   $who) }
			,	'variables'  => sub { varexpand(@_,    $who) }
			,	'devinfo'    => sub { devinfo(@_) }
			,	'atticlink'  => sub { atticlink(@_) }
			,	'encoding'   => sub { return $config->{'encoding'} }
			,	'LXRversion' => sub { return $LXRversion::LXRversion }
			,	'varaction'	 => sub { varaction($who) }
			,	'varparam'	 => sub { $hidden }
			)
		)
	);
}

sub makefooter {
	my $who = shift;
	my $tmplname;
	my $template = "<hr>\n</body>\n";

	$tmplname = $who . "tail";

	unless ($who ne "sourcedir" || $config->sourcedirtail) {
		$tmplname = "sourcetail";
	}
	unless ($config->value($tmplname)) {
		$tmplname = "htmltail";
	}

	if ($config->value($tmplname)) {
		if (open(TEMPL, $config->value($tmplname))) {
			local ($/) = undef;
			$template = <TEMPL>;
			close(TEMPL);
		} else {
			warning("Template " . $config->value($tmplname) . " does not exist in ".`pwd`);
		}
	}

	print(
		expandtemplate(
			$template,
			(	'banner'    => sub { bannerexpand(@_, $who) }
			,	'thisurl'   => sub { thisurl(@_) }
			,	'modes'     => sub { modeexpand(@_,   $who) }
			,	'variables' => sub { varexpand(@_,    $who) }
			,	'devinfo'   => sub { devinfo(@_) } 
			,	'LXRversion' => sub { return $LXRversion::LXRversion }
			,	'varaction'	 => sub { varaction($who) }
			,	'varparam'	 => sub { $hidden }
			)
		)
	);
}

# Send an error page in case source tree was not found
sub makeerrorpage {
	my $who = shift;
	my $tmplname;
	my $template = "<html><body><hr>\n"
		      . "<div align='center'>\n"
		      . "<h1>Unrecoverable Error</h1><br>\n"
		      . "\$tree unknown\n"
		      . "</div>\n</body></html>\n";

	$tmplname = $who;

	if ($config->value($tmplname)) {
		if (open(TEMPL, $config->value($tmplname))) {
			local ($/) = undef;
			$template = <TEMPL>;
			close(TEMPL);
		}
		else {
			warning("Template " . $config->value($tmplname) . " does not exist in ".`pwd`);
		}
	}

	print("Content-Type: text/html; charset=iso-8859-1\n");
	print("\n");

	my $treeextract = '([^/]*)/[^/]*$'; # default: capture before-last fragment
	if (exists ($config->{'treeextract'})) {
		$treeextract = $config->treeextract;
	}

	print(
		expandtemplate(
			$template,
			(
				'tree'    => sub { $_ = $ENV{'SCRIPT_NAME' }; m!$treeextract!; return $1; },
				'stylesheet' => sub { stylesheet(@_) },
			)
		)
	);
	$config = undef;
	$files  = undef;
	$index  = undef;
}

1;
