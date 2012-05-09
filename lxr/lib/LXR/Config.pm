# -*- tab-width: 4 -*-
###############################################
#
# $Id: Config.pm,v 1.50 2012/05/04 08:14:43 ajlittoz Exp $

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

=head1 Config module

This module contains the API to the configuration file.
It is responsible for reading the file, locating the
parameter group for the current source-tree and presenting
an abstract interface to the C<'variables'>.

=cut

package LXR::Config;

$CVSID = '$Id: Config.pm,v 1.50 2012/05/04 08:14:43 ajlittoz Exp $ ';

use strict;
use File::Path;

use LXR::Common;

require Exporter;

use vars qw($AUTOLOAD $confname);

$confname = 'lxr.conf';

sub new {
	my ($class, @parms) = @_;
	my $self = {};
	bless($self);
	if ($self->_initialize(@parms)) {
		return ($self);
	} else {
		return undef;
	}
}

sub readconfig {
	my $self = shift;
	my $confpath = $$self{'confpath'};

	unless (open(CONFIG, $confpath)) {
		die("Couldn't open configuration file \"$confpath\".");
	}

	local ($/) = undef;
	my $config_contents = <CONFIG>;
	$config_contents =~ /(.*)/s;
	$config_contents = $1;    #untaint it
	my @config = eval("\n#line 1 \"configuration file\"\n" . $config_contents);
	die($@) if $@;

	return wantarray ? @config : $config[0];
}

sub readfile {
	local ($/) = undef;    # Just in case; probably redundant.
	my $file = shift;
	my @data;

	open(INPUT, $file) || fatal("Config: cannot open $file\n");
	$file = <INPUT>;
	close(INPUT);

	@data = $file =~ /([^\s]+)/gs;

	return wantarray ? @data : $data[0];
}

sub _initialize {
	my ($self, $url, $confpath) = @_;
	my ($dir,  $arg);

	unless ($url) {
		$url = 'http://' . $ENV{'SERVER_NAME'} . ':' . $ENV{'SERVER_PORT'};
		$url =~ s/:80$//;
	}

	$url =~ s!^//!http://!;		# allow a shortened form in genxref
	$url =~ s!^http://([^/]*):443/!https://$1/!;
	$url .= '/' unless $url =~ m#/$#;    # append / if necessary

	unless ($confpath) {
		($confpath) = ($0 =~ /(.*?)[^\/]*$/);
		$confpath .= $confname;
	}

	unless (open(CONFIG, $confpath)) {
		die("Couldn't open configuration file \"$confpath\".");
	}

	$$self{'confpath'} = $confpath;

	local ($/) = undef;
	my $config_contents = <CONFIG>;
	$config_contents =~ /(.*)/s;
	$config_contents = $1;    #untaint it
	my @config = eval("\n#line 1 \"configuration file\"\n" . $config_contents);
	die($@) if $@;

	my $config;
	if (scalar(@config) > 0) {
		%$self = (%$self, %{ $config[0] });
	}

	$url =~ m!(^.*?://.*?)/!;	# host name and port used to access server
	my $host = $1;
		# To allow simultaneous Apache and lighttpd operation
		# on 2 different ports, remove port for identification
	$host =~ s/(:\d+|)$//;
	my $port = $1;
	my $script_path;
	if ($url) {
		($script_path = $url) =~ s!^.*?://[^/]*!!; # remove host and port
	} else {
		$script_path = $ENV{'SCRIPT_NAME'};
	}
	$script_path =~ s!/[^/]*$!!;	# path to script
	$script_path =~ s!^/*!/!;		# ensure a single starting /
	my $parmgroup = 0;
  CANDIDATE: foreach $config (@config[1..$#config]) {
		$parmgroup++;				# next parameter group
		my @hostnames;
		if (exists($config->{'host_names'})) {
			@hostnames = @{$config->{'host_names'}};
		} elsif (exists($self->{'host_names'})) {
			@hostnames = @{$self->{'host_names'}};
		};
		my $virtroot = $config->{'virtroot'};
		my $hits = $virtroot =~ s!/+$!!;	# ensure no ending /
		$hits += $virtroot =~ s!^/+!/!;		# and a single starting /
		if ($hits > 0) { $config->{'virtroot'} = $virtroot }
		if (scalar(@hostnames)>0) {
			foreach my $rt (@hostnames) {
				$rt =~ s!/*$!!;		# remove trailing /
				$rt =~ s!^//!http://!; # allow for a shortened form
		# To allow simultaneous Apache and lighttpd operation
		# on 2 different ports, remove port for identification
				$rt =~ s/:\d+$//;
				if	(	$host eq $rt
					&&	$script_path eq $virtroot
					) {
					$config->{'baseurl'} = $rt . $port . $script_path;
					%$self = (%$self, %$config);
					$$self{'parmgroupnr'} = $parmgroup;
					last CANDIDATE;
				}
			}
		} else { # elsif ($config->{'baseurl'}) {
		# To allow simultaneous Apache and lighttpd operation
		# on 2 different ports, remove port for identification
			$url =~ s/:\d+$//;
			my @aliases;
			if ($config->{'baseurl_aliases'}) {
				@aliases = @{ $config->{'baseurl_aliases'} };
			}
			my $root = $config->{'baseurl'};
			push @aliases, $root;
			foreach my $rt (@aliases) {
				$rt .= '/' unless $rt =~ m#/$#;    # append / if necessary
				$rt =~ s/:\d+$//;	# remove port (approximate match)
				my $r = quotemeta($rt);
				if ($url =~ /^$r/) {
					$rt =~ s/^$r/$rt$port/;
					$config->{'baseurl'} = $rt;
					%$self = (%$self, %$config);
					$$self{'parmgroupnr'} = $parmgroup;
					last CANDIDATE;
				}
			}
		}
	}

	if(!exists $self->{'baseurl'}) {
		$0 =~ m/([^\/]*)$/;
		if("genxref" ne $1) {
			return 0;
		}
		elsif($url =~ m!https?://.+\.!) {
			die "Can't find config for $url: make sure there is a 'baseurl' line that matches in lxr.conf\n";
		} else {
			# wasn't a url, so probably genxref with a bad --url parameter
			die "Can't find config for $url: " . 
			 	"the --url parameter should be a URL (e.g. http://example.com/lxr) and must match a baseurl line in lxr.conf\n";
		}
	}

	$$self{'encoding'} = "iso-8859-1" unless (exists $self->{'encoding'});

	if (!exists $self->{'filetype'}) {
		if (exists $self->{'filetypeconf'}) {
			unless (open(FILETYPE, $self->{'filetypeconf'})) {
				die("Couldn't open configuration file ".$self->{'filetypeconf'});
			}
			local ($/) = undef;
			my $contents = <FILETYPE>;
			$contents =~ /(.*)/s;
			$contents = $1;    #untaint it
			my $mapping = eval("\n#line 1 \"file mappings\"\n" . $contents);
			die($@) if $@;
			if (defined($mapping)) {
				%$self = (%$self, %$mapping);
			}
		}
 	}
	if (!exists $self->{'filetype'}) {
		die "No file type mapping in $confpath.\n"
			. "Please specify 'filetype' or 'filetypeconf' \n";
	}
	if (!exists $self->{'interpreters'}) {
		die "No script interpreter mapping in $confpath.\n"
			. "Please specify 'interpreters' or 'filetypeconf' \n";
	}

	# Set-up various directories as necessary
	_ensuredirexists($self->{'tmpdir'});

	if (exists $self->{'glimpsebin'} and exists $self->{'swishbin'}) {
		die "Both Glimpse and Swish have been specified in $confpath.\n"
			."Please choose one of them by commenting out either glimpsebin or swishbin.\n";
		
	} elsif (exists $self->{'glimpsebin'}) {    
		if (!exists($self->{'glimpsedir'})) {
			die "Please specify glimpsedirbase or glimpsedir in $confpath\n"
				unless exists($self->{'glimpsedirbase'});
			$self->{'glimpsedir'} = $self->{'glimpsedirbase'} . $self->{'virtroot'};
		}
		_ensuredirexists($self->{'glimpsedir'});
	} elsif (exists $self->{'swishbin'}) {    
		if (!exists($self->{'swishdir'})) {
			die "Please specify swishdirbase or swishdir in $confpath\n"
				unless exists($self->{'swishdirbase'});
			$self->{'swishdir'} = $self->{'swishdirbase'} . $self->{'virtroot'};
		}
		_ensuredirexists($self->{'swishdir'});
	} else {
	# Since free-text search is not operational with VCSes,
	# don't complain if not configured.
	die	"Neither Glimpse nor Swish have been specified in $confpath.\n"
		."Please choose one of them by specifing a value for either glimpsebin or swishbin.\n"
		unless $self->{'sourceroot'} =~ m!^[^/]+:! ;
	}
	return 1;
}

sub allvariables {
	my $self = shift;

	return keys(%{ $self->{variables} || {} });
}

sub variable {
	my ($self, $var, $val) = @_;

	$self->{variables}{$var}{value} = $val if defined($val);
	return $self->{variables}{$var}{value}
	  || $self->vardefault($var);
}

sub vardefault {
	my ($self, $var) = @_;

	if (exists($self->{variables}{$var}{default})) {
		return $self->{variables}{$var}{default}
	}
	if (ref($self->{variables}{$var}{range}) eq "CODE") {
		my @vr = varrange($var);
		return $vr[0] if scalar(@vr)>0; return "head"
	}
	return	$self->{variables}{$var}{range}[0];
}

sub vardescription {
	my ($self, $var, $val) = @_;

	$self->{variables}{$var}{name} = $val if defined($val);

	return $self->{variables}{$var}{name};
}

sub varrange {
	my ($self, $var) = @_;
	no strict "refs";	# ajl: temporary, I hope. Without it
						# following line fails in $var!

	if (ref($self->{variables}{$var}{range}) eq "CODE") {
		return &{ $self->{variables}{$var}{range} };
	}

	return @{ $self->{variables}{$var}{range} || [] };
}

sub varexpand {
	my ($self, $exp) = @_;
	$exp =~ s/\$\{?([a-zA-Z]\w*)\}?/$self->variable($1)/ge;

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

sub mappath {
	my ($self, $path, @args) = @_;
	return $path if !exists($self->{'maps'});
	my %oldvars;
	my ($m, $n);

	foreach $m (@args) {
		if ($m =~ /(.*?)=(.*)/) {
			$oldvars{$1} = $self->variable($1);
			$self->variable($1, $2);
		}
	}

	my $i = 0;
	while ($i < @{$self->{'maps'}}) {
		$m = ${$self->{'maps'}}[$i++];
		$n = ${$self->{'maps'}}[$i++];
 		$path =~ s/$m/$self->varexpand($n)/e;
	}

	while (($m, $n) = each %oldvars) {
		$self->variable($m, $n);
	}

	return $path;
}


=head2 C<unmappath ($path, @args)>

Function C<unmappath> attempts to undo the effects of C<mappath>.
It returns an abstract path suitable for a new processing by
C<mappath> with a new set of variables values.

=over

=item 1 C<$path>

a I<string> containing the file path to "invert".

=item 1 C<@args>

an I<array> containing strings of the form var=value defining
the context in which the C<'maps'> rules were applied.

=back

=head3 Algorithm

C<'maps'> rules are given as I<pattern> C<=E<gt> > I<replacement>
where I<replacement> may itself contain C<$I<var> > markers
asking for substitution by the designated variable value.

Tentatively I<inverting> C<mappath> processing means applying
"inverse" C<'maps'> rules in reverse order.

B<Note:>

=over

=item

From a theoretical point of view, this problem has no general
solution. It can be solved only under restrictive conditions,
i.e. information has not been irremediably lost after rule
application (consider what happens if you completely remove
a path fragment and its delimiter).

=back

The generated "inverted" rule has the following form:

transformed I<replacement> C<=E<gt> > transformed I<pattern>

=over

=item 1 transformed I<replacement>

=over

=item 1 C<$num> elements become C<.+?>, i.e. "match something, but not
too much" to avoid to "swallow" what is described after this
sub-pattern.

B<Note:>

=over

=item

It could be possible to be more specific through parsing this
original pattern and analysing the associated parenthesised
sequence.
However, this could be time-expensive and the final advantage
might not be worth the trouble.
Even the known C<'maps'> rules for kernel cross-referencing
do not use C<$num>.

=back

=item 1 C<$var> are replaced by the designated variable value.

=item 1 If the original pattern had C<^> (start) or C<$> (end)
position anchors, these are transfered.

=back

=item 1 transformed I<pattern>

=over

=item 1 Optional quantifiers C<?> or C<*> (and variants
suffixed with C<?> or C<+>)

If there is one, process the sequence from beginning to the
quantifier to remove the preceding C<(> C<)> parenthesised
block (proceeding carefully from innermost pair of parenthesis
to outermost), C<[> C<]> character range or single character.

B<Caveat:>

=over

=item

When a character is checked, care is taken to cope with
C<\>-I<escaped> characters but no effort is done to manage
longer escape sequences such as C<\000>, C<\x00> or any other
multi-character sequence.
Consequently, the above transformation WILL FAIL if any such
sequence is present in the original pattern.

=back

I<The sub-pattern is entirely removed because the corresponding
string can be omitted from the file path. We then do not bother
with creating a sensible string since it is optional.>

=item 1 Repeating quantifier C<+> (and variants
suffixed with C<?> or C<+>)

Quantifier is merely removed to leave a single occurrence of
the matching string.

=item 1 C<(> C<)> groups

Proceeding from innermost group to outermost, the first alternative
is kept and the others deleted. The parentheses, now useless
and, matter of fact, harmful, are erased.

=item 1 C<[> C<]> character ranges

Only the first character is kept.

I<If the specification is an exclusion range C<[^ E<hellip> ]>,
the range is replaced by character C<%>, without further parsing,
in the hope it does not appear in the range.>

=item 1 C<\> escaped characters

Depending on the character, the sequence is erased, replaced by
a conventional character (think of character classes) or by the
designator letter without the backslash.

B<Caveat:>

=over

=item

No effort is done to manage longer escape sequences such as
C<\000>, C<\x00> or any other multi-character sequence on the
ground that this escape sequence is also valid in the replacement
part of an C<s///> instruction.

However some multi-character sequences (e.g. C<\P>) are not valid
and will ruin the "inverse" rule but they are thought to be rather
rare in LXR context.

=back

=back

=back

The generated rule is then applied to C<$path>.

The effect is cumulated on all "inverse" rules and the final
C<$path> is returned as the value of this C<sub>.

=cut

sub unmappath {
	my ($self, $path, @args) = @_;
	return $path if	(!exists($self->{'maps'})
					|| scalar($self->allvariables)<2
					);
	my ($m, $n);
	my %oldvars;

#	Save current environment before switching to @args environment
	foreach $m (@args) {
		if ($m =~ /(.*?)=(.*)/) {
			$oldvars{$1} = $self->variable($1);
			$self->variable($1, $2);
		}
	}

	my $i = $#{$self->{'maps'}};
	while ($i >= 0) {
		$n = ${$self->{'maps'}}[$i--];
		$m = ${$self->{'maps'}}[$i--];
# 		if ($n =~ m/\$\{?[0-9]/) {
# 			warning("Unable to reverse 'maps' rule $m => $n");
# 		}
	# Transform the original "replacement" into a pattern
	#	Replace variable markers by their values
		$n = $self->varexpand($n);
	#	Use a generic sub-pattern for $number substitutions
		$n =~ s/\$\{?[0-9]+\}?/.+?/g;

	# Next transform the original "pattern" into a replacement
	#	Remove x* or x? fragments since they are optional
		$m =~ s/((?:\\.|[^*?])+)[*?][+?]?/{
			my $pre = $1;
	#	( ... ) sub-pattern
			if ($pre =~ m!(\\.|[^\\])\)$!) {
	#	a- remove innermost ( ... ) blocks
				while ($pre =~ s!((?:^|\\.|[^\\])\((?:\\.|[^\(\)])*)\((?:\\.|[^\(\)])*\)!$1!) {};
	# 			                 1                ^                1 ^                 ^
	#	b- remove outer ( ... ) block
				$pre =~ s!(^|\\.|[^\\])\((?:\\.|[^\)])*\)$!$1!;
	#	[ ... ] sub-pattern
			} elsif ($pre =~ m!(\\.|[^\\])\]$!) {
				$pre =~ s!(^|\\.|[^\\])\[(?:\\.|[^\]])+\]$!$1!;
	#	single character or class
			} else {
				$pre =~ s!\\?.$!!;
			}
			$pre;
		}/ge;
		$m =~ s!(^|[^\\])\(\)!$1!;
	#	Remove + quantifiers since a single occurrence is enough
		$m =~ s/(\\.|[^+])\+[+?]?/$1/g;
	#	Process block constructs
	#	( ... ) sub-pattern: replace by first alternative
		while ($m =~ m!(^|\\.|[^\\])\(!) {
	#	a- process innermost, i.e. non-nested, ( ... ) blocks
			while ($m =~ s!((?:^|\\.|[^\\])\((?:\\.|[^\(\)])*)\(((?:\\.|[^\(\)\|])+)\|?(?:\\.|[^\(\)])*\)!$1$2!) {};
		#	               1                ^                1 ^2                  2                    ^
	#	b- process the remaining outer ( ... ) block
			$m =~ s!(^|\\.|[^\\])\(((?:\\.|[^\)\|])+)(?:\|(?:\\.|[^\(\)])*)?\)!$1$2!;
#			        1           1 ^2                2                        ^
		}
	#	[ ... ] sub-pattern: replace by one character
		$m =~ s!(^|\\.|[^\\])\[(\\.|[^\]])(?:\\.|[^\\])*\]!
			# Heuristic attempt to handle [^range]
			if ($2 eq "^") {
				$2 = "%";
			}
			$1 . $2;
				!ge;
	#	\x escaped character
	# NOTE: not handled g k N p P X o x
		$m =~ s!\\[AbBCEGKlLQuUzZ]!!g;
		$m =~ s!\\w!A!g;
		$m =~ s!\\d!0!g;
		$m =~ s!\\D!=!g;
		$m =~ s!\\W!&!g;
		$m =~ s!\\[hs]! !g;
		$m =~ s!\\([HNSV])!$1!g;
		$m =~ s!\\v!\n!g;
		$m =~ s!\\([^0-9abcdefghklnoprstuvwxzABCDEGHKLNPQRSUVWXZ])!$1!g;

	# Finally, transfer position information from original pattern
	# to new pattern (i.e. start and end tags)
		$n = "^" . $n if $m =~ s/^\^//;
		$n .= "\$" if $m =~ s/\$$//;

	# Apply the generated rule
		$path =~ s/$n/$m/;
	}

#	Restore original environment
	while (($m, $n) = each %oldvars) {
		$self->variable($m, $n);
	}

	return $path;
}


=head2 C<_ensuredirexists ($chkdir)>

Function C<_ensuredirexists> checks that directory C<$dir> exists
and creates it if not in a way similar to "C<mkdir -p>".

=over

=item 1 C<$chkdir>

a I<string> containing the directory path.

=back

=head3 Algorithm

Every component of the path is checked from left to right.
Both OS-absolute or relative paths are accepted, though the
latter form would probably not make sense in LXR context.

=cut

sub _ensuredirexists {
	my $chkdir = shift;
	my $dir;
	while ($chkdir =~ s:(^/?[^/]+)::) {
		$dir .= $1;
		if(!-d $dir) {
			mkpath($dir)
			or die "Couldn't make the directory $dir: ?!";
		}
	}  
}


1;
