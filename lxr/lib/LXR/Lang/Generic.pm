# -*- tab-width: 4 -*- ###############################################
#
# $Id: Generic.pm,v 1.30 2011/12/17 14:03:16 ajlittoz Exp $
#
# Implements generic support for any language that ectags can parse.
# This may not be ideal support, but it should at least work until
# someone writes better support.
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

package LXR::Lang::Generic;

$CVSID = '$Id: Generic.pm,v 1.30 2011/12/17 14:03:16 ajlittoz Exp $ ';

use strict;
use LXR::Common;
use LXR::Lang;

use vars qw($AUTOLOAD);

my $generic_config;

@LXR::Lang::Generic::ISA = ('LXR::Lang');

sub new {
	my ($proto, $pathname, $releaseid, $lang) = @_;
	my $class = ref($proto) || $proto;
	my $self = {};
	bless($self, $class);
	$$self{'releaseid'}  = $releaseid;
	$$self{'language'} = $lang;

	read_config() unless defined $generic_config;
	%$self = (%$self, %$generic_config);

	# Set langid
	$$self{'langid'} = $self->langinfo('langid');
	die "No langid for language $lang" if !defined $self->langid;

	# Make sure that at least a default identifier definition exists
	#	default must also cover C and C++ reserved words and Perl -variables
	$$self{'langmap'}{$lang}{'identdef'} = '[-\w~\#][\w]*'
		unless defined $self->langinfo('identdef');

	return $self;
}

# This is only executed once, saving the overhead of processing the
# config file each time.
#ajl111217 - Moved ctags version checking to genxref since testing here
#	caused problems on sourceforge
sub read_config {
	open(CONF, $config->genericconf) || die "Can't open " . $config->genericconf . ", $!";

	local ($/) = undef;

	my $config_contents = <CONF>;
	$config_contents =~ /(.*)/s;
	$config_contents = $1;                                                        #untaint it
	$generic_config  = eval("\n#line 1 \"generic.conf\"\n" . $config_contents);
	die($@) if $@;
	close CONF;

	# Setup the ctags to declid mapping
	my $langmap = $generic_config->{'langmap'};
	foreach my $lang (keys %$langmap) {
		my $typemap = $langmap->{$lang}{'typemap'};
		foreach my $type (keys %$typemap) {
			$typemap->{$type} = $index->decid($langmap->{$lang}{'langid'}, $typemap->{$type});
		}
	}
}

sub indexfile {
	my ($self, $name, $path, $fileid, $index, $config) = @_;

	my $typemap = $self->langinfo('typemap');

	my $langforce = ${ $self->eclangnamemapping }{ $self->language };
	if (!defined $langforce) {
		$langforce = $self->language;
	}

	if ($config->ectagsbin) {
		open(CTAGS,
			join(" ",
				$config->ectagsbin, $self->ectagsopts, "--excmd=number",
				"--language-force=$langforce", "-f", "-", $path, "|")
		  )
		  or die "Can't run ectags, $!";

		while (<CTAGS>) {
			chomp;

			my ($sym, $file, $line, $type, $ext) = split(/\t/, $_);
			$line =~ s/;\"$//;  #" fix fontification
			$ext  =~ /language:(\w+)/;
			$type = $typemap->{$type};
			if (!defined $type) {
				print "Warning: Unknown type ", (split(/\t/, $_))[3], "\n";
				next;
			}

			# TODO: can we make it more generic in parsing the extension fields?
			if (defined($ext) && $ext =~ /^(struct|union|class|enum):(.*)/) {
				$ext = $2;
				$ext =~ s/::<anonymous>//g;
			} else {
				$ext = undef;
			}

			$index->setsymdeclaration($sym, $fileid, $line, $self->langid, $type, $ext);
		}
		close(CTAGS);

	}
}

# This method returns the regexps used by SimpleParse to break the
# code into different blocks such as code, string, include, comment etc.
# Since this depends on the language, it's configured via generic.conf
sub parsespec {
	my ($self) = @_;
	my @spec = $self->langinfo('spec');
	return @spec;
}

# Process an include directive
# If no 'include' specification in generic.conf, proceed as in Lang.pm
# TODO: is there a way to call the base method so that there is no
#		maintenance issue? (parallel modifications in 2 locations)
# 'include' pattern must provide exactly 5 capture buffers:
#	$1	directive name
#	$2	spacer
#	$3	left delimiter
#	$4	include object
#	$5	right delimiter
# The "include object" can be transformed with 'first', 'global' and 'last'
# substitutions before being handed to incref where the path can further
# be manipulated with 'ignoredirs', 'incprefix' and 'maps'.
sub processinclude {
	my ($self, $frag, $dir) = @_;

	my $source = $$frag;
	my $dirname;	# include directive name
	my $spacer;		# spacing
	my $file;		# language include file
	my $path;		# OS include file
	my $lsep;		# left separator
	my $rsep;		# right separator
	my $m;			# matching pattern
	my $s;			# substitution string

	my $incspec = $self->langinfo('include');
	unless (defined $incspec) {
		$self->SUPER::processinclude ($frag, $dir);
		return;
	}

	if (defined $incspec) {
		my $patdir = $incspec->{'directive'};
		$source =~ s/^$patdir//s;	# remove directive
		$dirname = $1;
		$spacer  = $2;
		$lsep    = $3;
		$file    = $4;
		$path    = $4;
		$rsep    = $5;
		my @pat;

		if ($incspec->{'first'}) {
			@pat = @{$incspec->{'first'}};
			while (@pat) {
				($m, $s) = @pat[0, 1];
				shift @pat; shift @pat;
				last if (!$s);
				$path =~ s@$m@$s@;
			}
		}

		if ($incspec->{'global'}) {
			@pat = @{$incspec->{'global'}};
			while (@pat) {
				($m, $s) = @pat[0, 1];
				shift @pat; shift @pat;
				last if (!$s);
				$path =~ s@$m@$s@g;
			}
		}

		if ($incspec->{'last'}) {
			@pat = @{$incspec->{'last'}};
			while (@pat) {
				($m, $s) = @pat[0, 1];
				shift @pat; shift @pat;
				last if (!$s);
				$path =~ s@$m@$s@;
			}
		}
	}
	else {
	$source =~ s/^					# reminder: no initial space in the grammar
				([\w\#]\s*[\w]*)	# reserved keyword for include construct
				(\s+)				# space
				(?|	(\")(.+?)(\")	# C syntax
				|	(\0<)(.+?)(\0>)	# C alternate syntax
				|	()([\w:]+)(\b)	# Perl and others
				)
				//sx ;
		$dirname = $1;
		$spacer  = $2;
		$lsep    = $3;
		$file    = $4;
		$path    = $4;
		$rsep    = $5;
	}
	$$frag =	( $self->isreserved($dirname)
				? "<span class='reserved'>$dirname</span>"
				: $dirname
				)
			.	$spacer . $lsep
			.	&LXR::Common::incref($file, "include" ,$path ,$dir)
			.	$rsep
			. $source;		# tail if any (e.g. in Perl)
}

# Process a chunk of code
# Basically, look for anything that looks like an identifier, and if
# it is then make it a hyperlink, unless it's a reserved word in this
# language.
# Parameters:
#   $code - reference to the code to markup
#   @itag - ???

sub processcode {
	my ($self, $code) = @_;
	my ($start, $id);

	my $source = $$code;
	my $answer = '';
	my $identdef = $self->langinfo('identdef');

# Repeatedly remove what looks like an identifier from the head of
# the source line and mark it if it is a reserved word or known 
# identifier.
# NOTE: loop instead of s///g to prevent the substituted string
#		from being rescanned and HTML tags being eventually
#		marked themselves.
# NOTE: processreserved is inlined to proceed with the different
#		markings simultaneously to avoid interferences;
#		second reason, $2 is not a reference

	while ( $source =~ s/^(.*?)($identdef)\b//s)
	{
		$answer .= "$1" .
		( $self->isreserved($2)
		? "<span class='reserved'>$2</span>"
		: 
		   ( $index->issymbol($2, $$self{'releaseid'})
		   ? join($2, @{$$self{'itag'}})
		   : $2
		   )
		);
	}
	# don't forget the last chunk of the line containing no target
	$$code = $answer . $source;
}

sub isreserved {
	my ($self, $frag) = @_;

	$frag =~ s/\s//g ;        # for those who write # include
	foreach my $word (@{$self->langinfo('reserved')})
	{
		return 1 if $frag eq $word;
	}
	return 0;
}

sub processreserved {
	my ($self, $frag) = @_;

  # Replace reserved words
  $$frag =~ 
    s{
       (^|[^\$\w\#])([-\w~\#][\w]*)\b 
     }
     {
       $1.
       ( $self->isreserved($2) ? "<span class='reserved'>$2</span>" : $2 );
     }gex;
}

#
# Find references to symbols in the file
#

sub referencefile {
	my ($self, $name, $path, $fileid, $index, $config) = @_;

	require LXR::SimpleParse;

	# Use dummy tabwidth here since it doesn't matter for referencing
	&LXR::SimpleParse::init(new FileHandle($path), 1, $self->parsespec);

	my $linenum = 1;
	my ($btype, $frag) = &LXR::SimpleParse::nextfrag;
	my @lines;
	my $ls;

	while (defined($frag)) {
		@lines = ($frag =~ /(.*?\n)/g, $frag =~ /([^\n]*)$/);

		if (defined($btype)) {
			if ($btype eq 'comment' or $btype eq 'string' or $btype eq 'include') {
				$linenum += @lines - 1;
			} else {
				print "BTYPE was: $btype\n";
			}
		} else {
			my $l;
			my $string;
			foreach $l (@lines) {
				foreach (
					$l =~ /(?:^|[^a-zA-Z_\#]) 	# Non-symbol chars.
				 (\~?_*[a-zA-Z][a-zA-Z0-9_]*) # The symbol.
				 \b/ogx
				  )
				{
					$string = $_;

					#		  print "considering $string\n";
					if (!$self->isreserved($string) && $index->issymbol($string, $$self{'releaseid'}))
					{

						#			print "adding $string to references\n";
						$index->setsymreference($string, $fileid, $linenum);
					}

				}

				$linenum++;
			}
			$linenum--;
		}
		($btype, $frag) = &LXR::SimpleParse::nextfrag;
	}
	print("+++ $linenum\n");
}

# Autoload magic to allow access using $generic->variable syntax
# blatently ripped from Config.pm - I still don't fully understand how
# this works.

sub variable {
	my ($self, $var, $val) = @_;

	$self->{variables}{$var}{value} = $val if defined($val);
	return $self->{variables}{$var}{value}
	  || $self->vardefault($var);
}

sub varexpand {
	my ($self, $exp) = @_;
	$exp =~ s/\$\{?(\w+)\}?/$self->variable($1)/ge;

	return $exp;
}

sub value {
	my ($self, $var) = @_;

	if (exists($self->{$var})) {
		my $val = $self->{$var};

		if (ref($val) eq 'ARRAY') {
			return map { $self->varexpand($_) } @$val;
		} elsif (ref($val) eq 'CODE') {
			return $val;
		} else {
			return $self->varexpand($val);
		}
	} else {
		return undef;
	}
}

sub AUTOLOAD {
	my $self = shift;
	(my $var = $AUTOLOAD) =~ s/.*:://;

	my @val = $self->value($var);

	if (ref($val[0]) eq 'CODE') {
		return $val[0]->(@_);
	} else {
		return wantarray ? @val : $val[0];
	}
}

sub language {
	my ($self) = @_;
	return $self->{'language'};
}

sub langinfo {
	my ($self, $item) = @_;

	my $val;
	my $map = $self->langmap;
	die if !defined $map;
	if (exists $$map{ $self->language }) {
		$val = $$map{ $self->language };
	} else {
		return undef;
	}

	if (defined $val && defined $$val{$item}) {
		if (ref($$val{$item}) eq 'ARRAY') {
			return wantarray ? @{ $$val{$item} } : $$val{$item};
		}
		return $$val{$item};
	} else {
		return undef;
	}
}

1;
