# -*- tab-width: 4 -*-
###############################################
#
# $Id: Generic.pm,v 1.41 2013/04/12 15:01:09 ajlittoz Exp $
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
#
###############################################

=head1 Generic language module

This module is a generic language highlighting engine.
It is driven by specifications read from file I<generic.conf>.

Since it is a class, it can be derived to serve custom needs,
such as speed optimisation on specific languages.

=cut

package LXR::Lang::Generic;

$CVSID = '$Id: Generic.pm,v 1.41 2013/04/12 15:01:09 ajlittoz Exp $ ';

use strict;
use FileHandle;
use LXR::Common;
use LXR::Lang;

my $generic_config;

our @ISA = ('LXR::Lang');


=head2 C<new ($pathname, $releaseid, $lang)>

Method C<new> creates a new language object.

=over

=item 1 C<$pathname>

a I<string> containing the name of the file to parse

=item 1 C<$releaseid>

a I<string> containing the release (version) of the file to parse

=item 1 C<$lang>

a I<string> which is the I<key> for the specification I<hash>
C<'langmap'> in file I<generic.conf>

=back

This method is called by C<Lang>'s C<new> method but the thirs argument
is different! The returned object will be C<Lang>'s value.

The full unfiltered content of I<generic.conf> is stored in the
object structure.

To make sure identifiers can be recognised, a default pattern
(covering at least C/C++ and Perl) is copied into the language
specification if none is found.

=cut

sub new {
	my ($proto, $pathname, $releaseid, $lang) = @_;
	my $class = ref($proto) || $proto;
	my $self = {};
	bless($self, $class);
	$$self{'releaseid'}  = $releaseid;
	$$self{'language'} = $lang;

# 	read_config() unless defined $generic_config;
	if	(  $index->deccount() <= 0	# Necessary for --allurls processing
		|| !defined($generic_config)
		) {
	read_config();
	}
	%$self = (%$self, %$generic_config);

	# Set langid
	$$self{'langid'} = $self->langinfo('langid');
	die "No langid for language $lang" unless defined $self->{'langid'};

	# Make sure that at least a default identifier definition exists
	#	default must also cover C and C++ reserved words and Perl -variables
	$$self{'langmap'}{$lang}{'identdef'} = '[-\w~\#][\w]*'
		unless defined $self->langinfo('identdef');
	return $self;
}


=head2 C<read_config ()>

Internal function (not method!) C<read_config> reads in language
descriptions from configuration file.

This is only executed once, saving the overhead of processing the
config file each time.

The mapping between I<ctags> tags and their human readable counterpart
is stored in the database for every language. The mapping is then
replaced by the index of the table in the DB.

=cut

sub read_config {
	open(CONF, $config->genericconf) || die "Can't open " . $config->genericconf . ", $!";

	local ($/) = undef;

	my $config_contents = <CONF>;
	$config_contents =~ m/(.*)/s;
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
	$index->commit();
}


=head2 C<indexfile ($name, $path, $fileid, $index, $config)>

Method C<indexfile> is invoked during I<genxref> to parse and collect
the definitions in a file.

=over

=item 1 C<$name>

a I<string> containing the LXR file name

=item 1 C<$path>

a I<string> containing the OS file name

When files are stored in VCSes, C<$path> is the name of a temporary file.

=item 1 C<$fileid>

an I<integer> containing the internal DB id for the file/revision

=item 1 C<$index>

a I<reference> to the index (DB) object

=itm 1 C<$config>

a I<reference> to the configuration objet

=back

The effective job is done by I<ctags>. This method is only a
wrapper around I<ctags> to retrieve its results and store them
in the database.

=cut

sub indexfile {
	my ($self, $name, $path, $fileid, $index, $config) = @_;

	my $typemap = $self->langinfo('typemap');
	my $insensitive = $self->flagged('case_insensitive');

	my $langforce = ${ $self->{'eclangnamemapping'} }{ $self->language };
	if (!defined $langforce) {
		$langforce = $self->language;
	}

	# Launch ctags
	if ($config->{'ectagsbin'}) {
		open(CTAGS,
			join	( " "
					, $config->{'ectagsbin'}
					, @{$self->{'ectagsopts'}}
					, "--excmd=number"
					, "--language-force=$langforce"
					, "-f"
					, "-"
					, $path
					, "|"
					)
		  )
		  or die "Can't run ectags, $!";

	# Parse the results
		while (<CTAGS>) {
			chomp;

			my ($sym, $file, $line, $type, $ext) = split(/\t/, $_);
			$line =~ s/;\"$//;  #" fix fontification
			$ext  =~ m/language:(\w+)/;
			$type = $typemap->{$type};
			if (!defined $type) {
				print "Warning: Unknown type ", (split(/\t/, $_))[3], "\n";
				next;
			}

			# TODO: can we make it more generic in parsing the extension fields?
			if (defined($ext) && $ext =~ m/^(struct|union|class|enum):(.*)/) {
				$ext = $2;
				$ext =~ s/::<anonymous>//g;
				$ext = uc($ext) if $insensitive;
			} else {
				$ext = undef;
			}

			$sym = uc($sym) if $insensitive;
			$index->setsymdeclaration($sym, $fileid, $line, $self->{'langid'}, $type, $ext);
		}
		close(CTAGS);

	}
}


=head2 C<parsespec ()>

Method C<parsespec> returns the list of category specification for
this language.

The language specification is a list of I<hashes> describing the
delimiters for the different categories, such as code, string,
include, comment etc.

Each category is defined by a set of 2 or 3 regexps describing
the delimiters: opening, ending and optionnaly locking delimiters.

=cut

sub parsespec {
	my ($self) = @_;
	my @spec = $self->langinfo('spec');
	return @spec;
}


=head2 C<flagged ($flag)>

Method C<flagged> returns true (1) if the designated flag is
present in the language-specific I<hash> C<'flags'>.

=over

=item 1 C<$flag>

a I<string> containing the flag name

=back

=cut

sub flagged {
	my ($self, $flag) = @_;
	my @flags = $self->langinfo('flags');
	for (@flags) {
		return 1 if $_ eq $flag;
	}
	return 0;
}


=head2 C<processinclude ($frag, $dir)>

Method C<processinclude> is invoked to process a generic I<include> directive.

=over

=item 1 C<$frag>

a I<string> containing the directive

=item 1 C<$dir>

an optional I<string> containing a preferred directory for the include'd file

=back

Algorithm:

=over

Since it is generic, the process is driven by language-specific
parameters taken in I<hash> C<'include'> from the configuration
file.

B<CAUTION!> I<<Remember that the include fragment has already been
isolated by the parser through subhash C<'include'> of C<'spec'>.
This C<'include'> is a different hash, not a sub-hash.>>

We first make use of C<'directive'> which is a regular expression
allowing to split the include instruction or directive into 5 components:

=over

=item 1 directive name

=item 1 spacer

=item 1 left delimiter (may be void for some languages)

=item 1 included object

=item 1 right delimiter (may be void for some languages)

=back

To have something useful with LXR, the included object designation
has to be transformed into a file name. This is done by C<'first'>,
C<'global'> and C<'last'> optional rewrite rules. They are respectively
applied once at the beginning, repetitively as much as possible and
once at the end.

I<Do not be too smart with these rewrite rules. They only aim at
transforming language syntax into file designation. Elaborate
path processing is available with> C<'incprefix'>I<,> C<'ignoredirs'>
I< and >C<'maps'> I<processed by the link builder.>

When done, C<<E<lt>AE<gt> >> links to the file and all intermediate
directories are build.

=back

B<Note:>

=over

If no C<'include'> I<hash> is defined for this language, an internal
C<'directive'> matching C/C++ and Perl syntax is used.

=back

=cut

sub processinclude {
	my ($self, $frag, $dir) = @_;

	my $source = $$frag;
	my $dirname;	# include directive name
	my $spacer;		# spacing
	my $file;		# language include file
	my $psep;		# language-specific path separator
	my $path;		# OS include file
	my $lsep;		# left separator
	my $rsep;		# right separator
	my $m;			# matching pattern
	my $s;			# substitution string
	my $link;		# link to include file
	my $identdef = $self->langinfo('identdef');

	my $incspec = $self->langinfo('include');
	if (defined $incspec) {
		my $patdir = $incspec->{'directive'};
		if ($source !~ s/^$patdir//s) {		# Parse directive
			# Guard against syntax error or unexpected variant
			# Advance past keyword, so that parsing may continue without loop.
			$source =~ s/^($identdef)//;	# Erase keyword
			$dirname = $1;
			$$frag =	"<span class='reserved'>$dirname</span>";
			&LXR::SimpleParse::requeuefrag($source);
			return;
		}

		$dirname = $1;
		$spacer  = $2;
		$lsep    = $3;
		$file    = $4;
		$path    = $4;
		$rsep    = $5;

		my @pat;
		if ($incspec->{'pre'}) {
			@pat = @{$incspec->{'pre'}};
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

		if ($incspec->{'separator'}) {
			$psep = $incspec->{'separator'};
			$path =~ s@$psep@/@g;
		} else {
			$psep = '/';
		}

		if ($incspec->{'post'}) {
			@pat = @{$incspec->{'post'}};
			while (@pat) {
				($m, $s) = @pat[0, 1];
				shift @pat; shift @pat;
				last if (!$s);
				$path =~ s@$m@$s@;
			}
		}
	} else {
		# If no include definition, defaults to
		# 	directive_name  <...spacing...> file_name
		# file_name will be supposed to use default OS path separator
		if ($source !~ s/^					# reminder: no initial space in the grammar
						([\w\#]\s*[\w]*)	# reserved keyword for include construct
						(\s+)				# space
						(\S+)				# file without delims
						//sx) {
			# The default scheme may be totally inadapted to the current language,
			# advance past keyword, so that parsing may continue without loop.
			$source =~ s/^($identdef)//;	# Erase keyword
			$dirname = $1;
			$$frag =	"<span class='reserved'>$dirname</span>";
			&LXR::SimpleParse::requeuefrag($source);
			return;
		}

		$dirname = $1;
		$spacer  = $2;
		$lsep    = '';
		$file    = $3;
		$path    = $file;
		$rsep    = '';
		$psep    = '/';
	}
# 	$link = &LXR::Common::incref($file, "include", $path, $dir);
	$link = $self->_linkincludedirs
				( &LXR::Common::incref
					($file, "include", $path, $dir)
				, $file
				, $psep
				, $path
				, $dir
				);

	# Rescan the tail for more "code" constructs
	&LXR::SimpleParse::requeuefrag($source);

	# Reconstruct the highlighted fragment
	$$frag =	( $self->isreserved($dirname)
				? "<span class='reserved'>$dirname</span>"
				: $dirname
				)
			.	$spacer . $lsep
			.	$link
			.	$rsep
}


=head2 C<processcode ($code)>

Method C<processcode> is invoked to process the fragment as generic code.

=over

=item 1 C<$code>

a I<string> to mark

=back

Basically, look for anything that looks like an identifier, and if
it is then make it a hyperlink, unless it's a reserved word in this
language.

=cut

sub processcode {
	my ($self, $code) = @_;
	my ($start, $id);

	my $source = $$code;
	my $answer = '';
	my $identdef = $self->langinfo('identdef');
	my $insensitive = $self->flagged('case_insensitive');

# Repeatedly remove what looks like an identifier from the head of
# the source line and mark it if it is a reserved word or known 
# identifier.
# NOTE: loop instead of s///g to prevent the substituted string
#		from being rescanned and HTML tags being eventually
#		marked themselves.
# NOTE: processreserved is inlined to proceed with the different
#		markings simultaneously to avoid interferences;
#		second reason, $2 is not a reference

	while ( $source =~ s/^(.*?)($identdef)//s)
	{
		my $dictsymbol = $2;
		$dictsymbol = uc($dictsymbol) if $insensitive;
		$answer .= "$1" .
		( $self->isreserved($2)
		? "<span class='reserved'>$2</span>"
		:	( $index->issymbol($dictsymbol, $$self{'releaseid'})
			? join($2, @{$$self{'itag'}})
			: $2
			)
		);
	}
	# don't forget the last chunk of the line containing no target
	$$code = $answer . $source;
}


=head2 C<isreserved ($frag)>

Method C<isreserved> returns true (1) if the word is present in
the language-specific C<'reserved'> list.

=over

=item 1 C<$frag>

a I<string> containing the word to check

=back

In the case of a case-insensitive language, comparisons are made
betwwen upper case versions of the words.

=cut

sub isreserved {
	my ($self, $frag) = @_;

	$frag =~ s/\s//g ;        # for those who write # include
	if ($self->flagged('case_insensitive')) {
		$frag = uc($frag);
		foreach my $word (@{$self->langinfo('reserved')}) {
			$word = uc($word);
			return 1 if $frag eq $word;
		}
	} else {
		foreach my $word (@{$self->langinfo('reserved')}) {
			return 1 if $frag eq $word;
		}
	}
	return 0;
}


=head2 C<referencefile ($name, $path, $fileid, $index, $config)>

Method C<referencefile> is invoked during I<genxref> to parse and collect
the references in a file.

=over

=item 1 C<$name>

a I<string> containing the LXR file name

=item 1 C<$path>

a I<string> containing the OS file name

When files are stored in VCSes, C<$path> is the name of a temporary file.

=item 1 C<$fileid>

an I<integer> containing the internal DB id for the file/revision

=item 1 C<$index>

a I<reference> to the index (DB) object

=itm 1 C<$config>

a I<reference> to the configuration objet

=back

Using I<SimpleParse>'s C<nextfrag>, it focuses on "untyped"
fragments (aka. code fragments) from which symbols are extracted.
User symbols, if already declared, are entered in the reference
data base.

=cut

sub referencefile {
	my ($self, $name, $path, $fileid, $index, $config) = @_;

	require LXR::SimpleParse;

	# Use dummy tabwidth here since it doesn't matter for referencing
	&LXR::SimpleParse::init	( FileHandle->new($path)
							, 1
							, $self->parsespec
							);

	my $linenum = 1;
	my ($btype, $frag) = &LXR::SimpleParse::nextfrag;
	my @lines;
	my $ls;
	my $identdef = $self->langinfo('identdef');
	my $insensitive = $self->flagged('case_insensitive');

	while (defined($frag)) {
		@lines = ($frag =~ m/(.*?\n)/g, $frag =~ m/([^\n]*)$/);

		if (defined($btype)) {
			if	(  $btype eq 'comment'
				|| $btype eq 'string'
				|| $btype eq 'include'
				) {
				$linenum += @lines - 1;
			} else {
				print "BTYPE was: $btype\n";
			}
		} else {
			my $l;
			my $string;
			foreach $l (@lines) {

				foreach ($l =~ m/($identdef)\b/og) {
					$string = $_;

			#		print "considering $string\n";
					if (!$self->isreserved($string)) {
					# setsymreference decides by itself to record the
					# the symbol as a reference or not, based on the
					# DB dictionary (stated otherwise: it does not add
					# new symbols to the existing dictionary.
			#			print "adding $string to references\n";
						$string = uc($string) if $insensitive;
						$index->setsymreference($string, $fileid, $linenum);
					}
				}
				$linenum++;
			}
			$linenum--;
		}
		($btype, $frag) = &LXR::SimpleParse::nextfrag;
	}
	print(STDERR "+++ $linenum\n");
}


=head2 C<language ()>

Method C<language> is a shorthand notation for
C<<$lang-E<gt>{'language'}>>.

=cut

sub language {
	my ($self) = @_;
	return $self->{'language'};
}


=head2 C<langinfo ($item)>

Method C<langinfo> is a shorthand notation to extract sub-I<hashes>
from language description C<{'langmap'}{'language'}>.

=over

=item 1 C<$item>

a I<string> containing the name of the looked for sub-hash

=cut

sub langinfo {
	my ($self, $item) = @_;

	my $val;
	my $map = $self->{'langmap'};
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
