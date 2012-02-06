# -*- tab-width: 4 -*- ###############################################
#
# $Id: Common.pm,v 1.86 2012/01/03 13:57:28 ajlittoz Exp $
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

package LXR::Common;

$CVSID = '$Id: Common.pm,v 1.86 2012/01/03 13:57:28 ajlittoz Exp $ ';

use strict;

require Exporter;

# use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS
#   $files $index $config $pathname $identifier $releaseid
#   $HTTP $wwwdebug $tmpcounter);

use vars qw($HTTP $wwwdebug $tmpcounter);

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

# our %EXPORT_TAGS = ('html' => [@EXPORT]);
# our %EXPORT_TAGS = ('html' => [@EXPORT_OK]);

require Local;
require LXR::SimpleParse;
require LXR::Config;
require LXR::Files;
require LXR::Index;
require LXR::Template;
require LXR::Lang;
require LXRversion;

our $config;
our $files;
our $index;
our $pathname;
our $releaseid;
our $identifier;
our $HTTP;

$wwwdebug = 0;

$tmpcounter = 23;

sub warning {
	my $msg = shift;
	my $c = join(", line ", (caller)[ 0, 2 ]);
	print(STDERR "[", scalar(localtime), "] warning: $c: $msg\n");
	$msg =~ s/</&lt;/g;
	$msg =~ s/>/&gt;/g;
	return ("<h4 class=\"warning\"><i>** Warning: $msg</i></h4>\n") if $wwwdebug;
	return '';
}

sub fatal {
	my $c = join(", line ", (caller)[ 0, 2 ]);
	print(STDERR "[", scalar(localtime), "] fatal: $c: $_[0]\n");
	print(STDERR '[@INC ', join(" ", @INC), ' $0 ', $0, "\n");
	print(STDERR '$config', join(" ", %$config), "\n") if ref($config) eq "HASH";
	print("<h4 class=\"fatal\"><i>** Fatal: $_[0]</i></h4>\n") if $wwwdebug;
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

	if ($line && $line > 0 && length($line) < 4) {
		$line = ('0' x (4 - length($line))) . $line;
	} else {
		$line = 0;
	}

	return ("<a class='$css' href=\"$config->{virtroot}/source$path"
		  . &urlargs(@args)
		  . ($line > 0 ? "#$line" : "")
		  . "\"\>$desc</a>");
}

sub diffref {
	my ($desc, $css, $path, @args) = @_;
	my ($darg, $dval);

	($darg, $dval) = $args[0] =~ /(.*?)=(.*)/;
	return ("<a class='$css' href=\"$config->{virtroot}/diff$path"
		  . &urlargs	( &nonvarargs()
						, ($darg ? "_diffvar=$darg" : "")
						, ($dval ? "_diffval=$dval" : "")
						)
		  . "\"\>$desc</a>");
}

sub idref {
	my ($desc, $css, $id, @args) = @_;
	return ("<a class='$css' href=\"$config->{virtroot}/ident"
		  . &urlargs	( ($id ? "_i=$id" : "")
						, &nonvarargs()
						, @args
						)
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

	if ($HTTP->{'param'}->{'_raw'}) {

		#FIXME - need more types here
		my %type = (
			'gif'  => 'image/gif',
			'html' => 'text/html',
			'jpg'  => 'image/jpeg',
			'png'  => 'image/png'
		);

		if ($pathname =~ /\.([^.]+)$/ && $type{$1}) {
			print("Content-Type: ", $type{$1}, "\n");
		} else {
			print("Content-Type: text/plain\n");
		}
	}
	else
	{
		print("Content-Type: text/html; charset=", $config->{'encoding'}, "\n");
	}

	print("Cache-Control: no-cache, must-revalidate\n");

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
	$HTTP->{'this_url'} .= $ENV{'SCRIPT_NAME'};
	my $script_path = $HTTP->{'this_url'};
	$script_path =~ s!/[^/]*$!!;
	$HTTP->{'this_url'} .= $ENV{'PATH_INFO'};
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

	$config     = new LXR::Config($script_path);
	unless (exists $config->{'sourceroot'}) {
		LXR::Template::makeerrorpage('htmlfatal');
		die "Can't find config for " . $HTTP->{'this_url'};
	}

	# override the 'variables' value if necessary
	foreach my $param (keys %{$HTTP->{'param'}}) {
		my $var = $param;
		next unless $var =~ s!^\$!!;
		if (exists($config->{'variables'}->{$var})) {
			if (exists($HTTP->{'param'}->{$var})) {
				$HTTP->{'param'}->{$var} = $HTTP->{'param'}->{$param};
			} else {
				$config->variable($_, $HTTP->{'param'}->{$param});
			}
		}
		delete $HTTP->{'param'}->{$param};
	}

	$files = new LXR::Files($config->sourceroot, $config->sourceparams);
	die "Can't create Files for " . $config->sourceroot if !defined($files);
	$index = new LXR::Index($config->dbname);
	die "Can't create Index for " . $config->dbname if !defined($index);

	foreach ($config->allvariables) {
		$config->variable($_, $HTTP->{'param'}->{$_}) if $HTTP->{'param'}->{$_};
		delete $HTTP->{'param'}->{$_};
	}

	$HTTP->{'param'}->{'_file'} = clean_path($HTTP->{'param'}->{'_file'});
	$pathname = fixpaths($HTTP->{'path_info'} || $HTTP->{'param'}->{'_file'});

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

1;
