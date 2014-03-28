# -*- tab-width: 4 -*-
###############################################
#
# $Id: CVS.pm,v 1.51 2013/11/08 14:22:25 ajlittoz Exp $
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

=head1 CVS module

This module subclasses the Files module for CVS repository.

See Files POD for method information.

Methods are sorted in the same order as in the super-class.

=cut

package LXR::Files::CVS;

$CVSID = '$Id: CVS.pm,v 1.51 2013/11/08 14:22:25 ajlittoz Exp $ ';

use strict;
use Time::Local;
use LXR::Common;

@LXR::Files::CVS::ISA = ('LXR::Files');

our %cvs;
our $cache_filename = '';
our $gnu_diff;
our @anno;

sub new {
	my ($self, $config) = @_;

	$self = bless({}, $self);
	$self->{'rootpath'} = substr($config->{'sourceroot'}, 4);
	$self->{'rootpath'} =~ s@/*$@@;
	$self->{'path'} = $config->{'cvspath'};
	
	unless (defined $gnu_diff) {

		# the rcsdiff command (used in getdiff) uses parameters only supported by GNU diff
		$ENV{'PATH'} = $self->{'path'};
		if (index (`rcsdiff --version 2>/dev/null`, 'GNU') >= 0) {
			$gnu_diff = 1;
		} else {
			$gnu_diff = 0;
		}
	}

	return $self;
}

sub getdir {
	my ($self, $pathname, $releaseid) = @_;
	my ($node, @dirs, @files);
	my $DIRH;
	my $real = $self->toreal($pathname, $releaseid);

	# Directories are real directories in CVS
	opendir($DIRH, $real) || return ();
	while (defined($node = readdir($DIRH))) {
		if (-d $real . $node) {
			next if $self->_ignoredirs($pathname, $node);
			$node = $node . '/';
			# The "Attic" directory is where CVS stores removed files
			# Add them just in case.
			if ($node eq 'Attic/') {
				push(@files, $self->getdir($pathname . $node, $releaseid));
			} else {
			# Directory to keep (unless empty): suffix name with a slash
				push(@dirs, $node)
				  unless defined($releaseid)
				  && $self->dirempty($pathname . $node, $releaseid);
			}
		# Consider only files managed by CVS (ending with ,v)
		} elsif	($node =~ m/(.*),v$/) {
			# Special care is needed to use standard _ignorefiles() filter.
			# CVS file names are created from original files by suffixing
			# with ',v'. Removing this suffix, we can proceed as usual.
				next if $self->_ignorefiles($pathname, $1);

			# For normal display (i.e. some revisions reachable from 'head'),
			# check if requested version is alive. Looking for the file
			# the "Attic" is not enough because a requested side-branch
			# may be dead while the main trunk revision is alive.
			# A file in the "Attic" means all revisions are dead.
			# NOTE:	same processing in toreal sub.
			#		Don't forget to change in case of update
			if (!$$LXR::Common::HTTP{'param'}{'_showattic'}) {
				$self->parsecvs($pathname . $1);
				my $rev = $cvs{'header'}{'symbols'}{$releaseid};
				if ($cvs{'branch'}{$rev}{'state'} eq 'dead') {
					next;
				}
			}
			# We have asserted this revision is alive, list the file.
			push(@files, $1)
			  if !defined($releaseid)
			  || $self->getfiletime($pathname . $1, $releaseid);
		}
	}
	closedir($DIRH);

	return (sort(@dirs), sort(@files));
}

sub getannotations {
	my ($self, $filename, $releaseid) = @_;

	$self->parsecvs($filename);

	my $rev = $self->filerev($filename, $releaseid);
	return () unless defined($rev);

	# In CVS, changes are kept relative in reverse chronological
	# order, starting from latest version 'head'.
	my $hrev = $cvs{'header'}{'head'};
	my $lrev;
	my @anno;
	#	In case, $releaseid is on a branch off the main trunk
	#	we must stop reconstruction at the branch point.
	$rev =~ s/(\d+\.\d+)//; # remove base ancestor
	my $arev = $1;			# ancestor revision on main trunk
	#	All we need is the number of lines in $filename.
	#	Unhappily, we have to read the file.
	my $headfh = $self->getfilehandle($filename, $hrev);
	my @head   = $headfh->getlines;
	#	Discard line content to guard against a number which could
	#	be mistaken for a line number and cause havoc later.
	@head = ('') x scalar(@head);

	while (1) {
		if ($arev eq $hrev) {	# found the ancestor, number the lines
			@head = 0 .. $#head if @head;
		}

		$lrev = $hrev;
		$hrev = $cvs{'branch'}{$hrev}{'next'} || last;

		#	Get the "directives" to construct hrev from lrev
		my @diff = $self->getdiff($filename, $lrev, $hrev);
		#	The lines-set @head is dynamically adjusted according to
		#	the directives. This changes the line numbers. $off tracks
		#	the adjustment factor between the original number in the
		#	directives and the current line number in @head after
		#	application of the previous directives
		my $off  = 0;

		while (@diff) {
			my $dir = shift(@diff);

			#	a pos nbr = add "nbr" lines at "pos" position
			if ($dir =~ m/^a(\d+)\s+(\d+)/) {
				splice(@diff, 0, $2);		# Discard real text
				splice(@head, $1 - $off, 0, ('') x $2);
				$off -= $2;					# Decrease adjustment
			#	d pos nbr = remove "nbr" lines at "pos" position
			} elsif ($dir =~ m/^d(\d+)\s+(\d+)/) {
				#	Record in @anno the revision the lines were entered
				map	{ $anno[$_] = $lrev if $_ ne '' }
					splice(@head, $1 - $off - 1, $2);
				$off += $2;					# Increase adjustment
			} else {
				warn('Oops! Out of sync!');
			}
		}
	}

	#	We have reached the trunk root. If @head is not empty,
	#	these lines where inserted at the very beginning.
	#	Mark them.
	#	ajl: commented out the test, so that annotations are always
	#	     edited; otherwise, initial text (revision 1.1) bears no
	#	     annotation (as it should since there is no ancestor).
# 	if (@anno) {
		map { $anno[$_] = $lrev if $_ ne ''; } @head;
# 	}

	#	If the requested release is on a branch, we must
	#	follow the branch up to the release or the next
	#	branching point.
	while ($rev ne '') {			# Target file is on a branch
		$lrev = $arev;
		$rev =~ m/(\.\d+)/;			# Get branch number
		$hrev = $arev . $1 . '.1';	# First commit
		$rev =~ s/(\.\d+\.\d+)//;	# Get branch root
		$arev .= $1;				# Destination revision or branch point

		while (1) {
			my @diff = $self->getdiff($filename, $lrev, $hrev);
			my $off  = 0;

			#	This loop is the same as the previous above
			while (@diff) {
				my $dir = shift(@diff);

				if ($dir =~ m/^a(\d+)\s+(\d+)/) {
					splice(@diff, 0, $2);
					splice(@anno, $1 + $off, 0, ($hrev) x $2);
					$off += $2;
				} elsif ($dir =~ m/^d(\d+)\s+(\d+)/) {
					splice(@anno, $1 + $off - 1, $2);
					$off -= $2;
				} else {
					warn('Oops! Out of sync!');
				}
			}
			last if $arev eq $hrev;	# Are we done on this branch?
			$lrev = $hrev;
			$hrev = $cvs{'branch'}{$hrev}{'next'};
		}
	}

	return @anno;
}

sub getnextannotation {
	my ($self, $filename, $releaseid) = @_;

	return shift @anno;
}

sub getauthor {
	my ($self, $filename, $releaseid, $revision) = @_;

	$self->parsecvs($filename);
	return $cvs{'branch'}{$revision}{'author'};
}

#	Returns a numeric file revision based on $releaseid:
#	- rev_9. ... .9	=> 9. ... .9 (rev_ stripped)
#	- 9. ... .9		=> 9. ... .9 (unchanged, unless on import branches)
#					=> 1.1       (for import branches to avoid trouble)
#	- other			=> 9. ... .9 (translated from control info)
#	To accept import branches would require some extensive work
#	which may not be worth it on this obsolete VCS.
sub filerev {
	my ($self, $filename, $releaseid) = @_;

	if ($releaseid =~ m/rev_([\d\.]+)/) {
		return $1;
	} elsif ($releaseid =~ m/^([\d\.]+)$/) {
		# Import branches are causing problem,
		# force initial version.
		if ($releaseid =~ m/^1\.1\.\d*\[13579]/) {
			return '1.1';
		}
		return $1;
	} else {
		$self->parsecvs($filename);
		return $cvs{'header'}{'symbols'}{$releaseid};
	}
}

#	getfilehandle returns a handle to a pipe through which the
#	checked out content can be read.
sub getfilehandle {
	my ($self, $filename, $releaseid, $withannot) = @_;
	my ($fileh);

	$self->parsecvs($filename);
	my $rev = $self->filerev($filename, $releaseid);
	return undef unless defined($rev);

	return undef unless defined($self->toreal($filename, $releaseid));

	if ($withannot) {
		@anno = $self->getannotations($filename, $releaseid);
	}

	$rev =~ m/([\d\.]*)/;
	$rev = $1;    # untaint
# 	my $clean_filename = $self->cleanstring($self->toreal($filename, $releaseid));
	my $clean_filename = $self->toreal($filename, $releaseid);
	$clean_filename =~ m/(.*)/;
	$clean_filename = $1;    # technically untaint here (cleanstring did the real untainting)

	$ENV{'PATH'} = $self->{'path'};
	# Option -q: quiet, no diagnostics printed
	open	( $fileh
			, '-|'
			, 'co', '-q'
			, '-p'.$rev
			, $clean_filename
# 			, '2>/dev/null'
			)
	or die('Error executing "co"; rcs not installed?');

	return $fileh;
}

#	Unhappily, computing the file size requires reading it.
sub getfilesize {
	my ($self, $filename, $releaseid) = @_;

	return length($self->getfile($filename, $releaseid));
}

#	getfiletime returns the time and date the file was committed
#	(extracted from control info).
sub getfiletime {
	my ($self, $filename, $releaseid) = @_;

	return undef if $self->isdir($filename, $releaseid);

	$self->parsecvs($filename);
	my $rev = $self->filerev($filename, $releaseid);
	return undef unless defined($rev);

	my @t = reverse(split(/\./, $cvs{'branch'}{$rev}{'date'}));
	return undef unless @t;

	$t[4]--;
	return timegm(@t);
}

sub isdir {
	my ($self, $pathname, $releaseid) = @_;

	return -d $self->toreal($pathname, $releaseid);
}

sub isfile {
	my ($self, $pathname, $releaseid) = @_;

	return -f $self->toreal($pathname, $releaseid);
}


=head2 C<toreal ($pathname, $releaseid)>

C<toreal> translate the pair C<$pathname>/C<$releaseid> into a
real full OS-absolute path.

=over

=item 1 C<$pathname>

a I<string> containing the path relative to C<'sourceroot'>

=item 1 C<$releaseid>

the release (or version) in which C<$pathname> is expected to
be found

=back

If C<$pathname> is located in some directory to ignore,
the result is C<undef>.
Otherwise, the result is the full OS path in the correct 'version'
directory.

B<Note:>

=over

=item

This function should not be used outside this module.

=back

=cut

sub toreal {
	my ($self, $pathname, $releaseid) = @_;
	my $real = $self->{'rootpath'} . $pathname;

	# If directory, nothing more to do
	return $real if -d $real;

	# For normal display (i.e. some revisions reachable from 'head'),
	# check if requested version is alive. Looking for the file
	# the "Attic" is not enough because a requested side-branch
	# may be dead while the main trunk revision is alive.
	# A file in the "Attic" means all revisions are dead.
	# NOTE:	same processing in getdir sub.
	#		Don't forget to change in case of update
	if (!$$LXR::Common::HTTP{'param'}{'_showattic'}) {
		$self->parsecvs($pathname);
		my $rev = $cvs{'header'}{'symbols'}{$releaseid};
		if ($cvs{'branch'}{$rev}{'state'} eq 'dead') {
			return undef;
		}
	}

	# Return the repository for the file
	return $real . ',v' if -f $real . ',v';

	# Not found, then may be in the "Attic"
	$real =~ s!(/[^/]+/?)$!/Attic$1!;

	return $real        if -d $real;
	return $real . ',v' if -f $real . ',v';

	return undef;
}

#
#		Private functions
#

=head2 C<getdiff ($filename, $release1, $release2)>

C<getdiff> returns the "instructions" (additions and erasures)
required to transform the file from C<$release1> to C<$release2>
version.

=over

=item 1 C<$filename>

a I<string> containing the filename

=item 1 C<$release1>

a I<string> containing the source version

=item 1 C<$release2>

a I<string> containing the final version

=back

The set of "instructions" is computed by shell command I<rcsdiff>.

=cut

sub getdiff {
	my ($self, $filename, $release1, $release2) = @_;
	my ($fileh);

	return () if $gnu_diff == 0;

	$self->parsecvs($filename);

	# Find the canonical revision number of the releases
	my $rev1 = $self->filerev($filename, $release1);
	return () unless defined($rev1);
	my $rev2 = $self->filerev($filename, $release2);
	return () unless defined($rev2);

	# Untaint arguments
	$rev1 =~ m/([\d\.]*)/;
	$rev1 = $1;    # untaint
	$rev2 =~ m/([\d\.]*)/;
	$rev2 = $1;    # untaint
# 	my $clean_filename = $self->cleanstring($self->toreal($filename, $releaseid));
	my $clean_filename = $self->toreal($filename, $release1);
	$clean_filename =~ m/(.*)/;
	$clean_filename = $1;    # technically untaint here (cleanstring did the real untainting)

	$ENV{'PATH'} = $self->{'path'};
	# Option -q: quiet, no diagnostics printed
	# Option -a: all files considered text files (diff option)
	# Option -n: RCS format for differences (diff option)
	open	( $fileh
			, '-|'
			, 'rcsdiff'
			, '-q', '-a', '-n'
			, '-r'.$rev1
			, '-r'.$rev2
			, $clean_filename
			);
	die('Error executing "rcsdiff"; rcs not installed?') unless $fileh;
	return $fileh->getlines;
}

=head2 C<dirempty ($pathname, $releaseid)>

C<dirempty> returns 1 (I<true>) if the directory is empty,
0 (I<false>) otherwise.

=over

=item 1 C<$pathname>

a I<string> containing the path

=item 1 C<$releaseid>

the release (or version) in which C<$pathname> is expected to
be found

=back

To determine if C<$pathname> is empty, the files contained therein are
checked for a valid revision and directories are recursively explored.
A valid revision is sufficient to decide non-empty directory.

If the algorithm reaches the end of content, directory is empty.

Contained subdirectories or files are not excluded by C<'ignoredirs'>
or C<'ignorefiles'> filters to give a visual feedback of directory
existence.
These subdirectories or files will be effectively excluded when
displaying the directory.

=cut

sub dirempty {
	my ($self, $pathname, $releaseid) = @_;
	my ($node, @dirs, @files);
	my $DIRH;
	my $real = $self->toreal($pathname, $releaseid);

	opendir($DIRH, $real) || return 1;
	while (defined($node = readdir($DIRH))) {
		# Build two lists: one with the subdirectories,
		# the other with CVS difference files.
		if (-d $real . $node) {
			push(@dirs, $node . '/');
		} elsif ($node =~ m/(.*),v$/) {
			push(@files, $1);
		}
	}
	closedir($DIRH);

	# Check the lists: on first alive file or non-empty subdirectory
	# return with non-empty status
	foreach $node (@files) {
		return 0 if $self->filerev($pathname . $node, $releaseid);
	}
	foreach $node (@dirs) {
		return 0 unless $self->dirempty($pathname . $node, $releaseid);
	}
	# We went through both lists, the directory is empty.
	return 1;
}

=head2 C<cleanstring ($in)>

C<cleanstring> returns its argument with all "dangerous" characters removed.

=over

=item 1 C<$in>

I<String> to clean

=back

"Dangerous" characters are those which have special meaning for the shell
such as C<$> (starting substitution), C<;> (statement separator), &hellip;

This is rather brute force since sophisticated escape rules could be
designed to leave full freedom to the user.
But till now, nobody complained.

=cut

sub cleanstring {
	my ($self, $in) = @_;

	my $out = '';
	for (split('', $in)) {
		s/[|&!`;\$%<>[:cntrl:]]//  ||    # drop these in particular
		  m/[\w\/,.-_+=]/          ||    # keep these intact
		  s/([ '"\x20-\x7E])/\\$1/ ||    # escape these out
		  s/.//;                         # drop everything else
		$out .= $_;
	}

	return $out;
}

=head2 C<allreleases ($filename)>

C<allreleases> returns a list of all I<releases> available for the designated
file.

=over

=item 1 C<$filename>

A I<string> containing the filename

=back

A I<release> is not a numeric I<revision>, it is specific user symbol.
It is a tag usually associated with a software release,
but may also name a branching point.

Two files with the same I<release> tag are in a consistent state.

For files, the list is extracted from C<'symbols'> control information.
Since CVS does not manage directory version, the release is arbitrarily
made of the C<'v'> URL argument (if it exists) and the default value
of variable C<'v'>.

=cut

sub allreleases {
	my ($self, $filename) = @_;

	$self->parsecvs($filename);

	if (exists $cvs{'header'}{'symbols'}) {
		return sort keys %{ $cvs{'header'}{'symbols'} };
	} else {
	# no header symbols for a directory, so we use the default and the current release
		my @releases;
		push @releases, $$LXR::Common::HTTP{'param'}{'v'} if $$LXR::Common::HTTP{'param'}{'v'};
		push @releases, $self->{'config'}->vardefault('v');
		return @releases;
	}
}

=head2 C<allrevisions ($filename)>

C<allrevisions> returns a list of all I<revisions> available for the designated
file.

=over

=item 1 C<$filename>

A I<string> containing the filename

=back

A I<revision> is a dot-separated set of numbers.
It is automatically generated by CVS at commit time.

I<Revision> numbers between files are not correlated.

For files, the list is extracted from C<'branch'> control information.
It is empty for directories.

=cut

sub allrevisions {
	my ($self, $filename) = @_;

	$self->parsecvs($filename);

	return sort byrevision keys(%{ $cvs{'branch'} });
}

=head2 C<byrevision ($a, $b)>

C<byrevision> is an auxiliary compare function for C<sort>.

=over

=item 1 C<$a>

=item 1 C<$b>

I<Strings> to compare (CVS revision numbers)

=back

I< This is an "ordinary" function, not a method
(no> C<$self> I<first argument).>

=cut

# sort by CVS version
sub byrevision {
	# Split rev numbers into arrays
	my @one = split /\./, $a;
	my @two = split /\./, $b;
	# Compare each array element, returning as soon as we find a difference
	for (my $i = 0; $i <= $#one; $i++) {
		my $ret = $one[$i] <=> $two[$i];
		return $ret if $ret;
	}

	# If still no difference after we ran through all elements of @one,
	# compare the length of the array
	return $#one <=> $#two;
}


=head2 C<parsecvs ($filename)>

C<parsecvs> builds a hash C<%cvs> which summarises control information
contained in the CVS difference file C<$filename>.

=over

=item 1 C<$filename>

A I<string> containing the filename

=back

B<Caveat:>

=over

=item

This method is indirectly recursive through C<toreal>.
Special precaution must be taken against infinite recursion.

=back

C<parsecvs> parses a CVS difference file
(a bit like I<rlog> does when listing content, but much less
thoroughly). It stops when it reaches the text.
Ideally, an I<rcs> tool would be better.

It is critical for good operation of CVS class.

=cut

sub parsecvs {
	my ($self, $filename) = @_;

	# Foolproof fence against infinite recursion
	return if $cache_filename eq $filename;
	$cache_filename = $filename;

	undef %cvs;

	my $file = '';
	open(CVS, $self->toreal($filename, undef));
	if (-d CVS) {
		close(CVS);
		return;		# we can't parse a directory
	}
	while (<CVS>) {
		if (m/^text\s*$/) {
			# stop reading when we hit the text.
			last;
		}
		$file .= $_;
	}
	close(CVS);

	# @cvs contains the list of "paragraphs".
	# A paragraph is a sequence of non-empty lines (containing
	# @-delimited strings or others sequences without @)
	# separated from the next by empty lines.
	my @cvs = $file =~ m/((?:(?:[^\n@]+|@[^@]*@)\n?)+)/gs;
#	                     12  3         3       3   2 1
#	                     ||  +---------+-------+   | |
#	                     |+------------------------+ |
	# The header is the first paragraph.
	# It is composed of "definitions" terminated by ;
	# Each "definition" begins with a keyword and continues with a
	# value made of @-delimited strings and other sequences.
	# The value may span several lines.
	# Since m/.../ extracts two strings each time, it effectively
	# builds a hash pair keyword/value.
	$cvs{'header'} = {
		map {	s/@@/@/gs;
				substr($_, 0, 1) eq '@' && substr($_, 1, -1) || $_
			# The previous two lines "unquote" the @-strings.
			} shift(@cvs) =~ m/(\w+)\s*((?:[^;@]+|@[^@]*@)*);/gs
#			                   +---+   12        2       2 1
#			                 keyword   +-------value-------+
	};

	# Replace the 'symbols' list of tag:revision by a hash for easier reference.
	$cvs{'header'}{'symbols'} =
		{ $cvs{'header'}{'symbols'} =~ m/(\S+?):(\S+)/g };

	my ($orel, $nrel, $rev);

		#	Scan the 'symbols' section to patch the map
		#	between symbols/tags and revision numbers.
		# 	Pay special attention to branch points.
	while (($orel, $rev) = each %{ $cvs{'header'}{'symbols'} }) {
		# $orel is symbol/tag
		# $rev is corresponding revision number

		#	Check if it is a branch tag (contributed by Blade)
		#	Branch numbers have a 0 in the second rightmost position
		#	(from CVS manual).
		if (index($rev, '.0.') >= 0) {		# simplified test
			(my $branchprefix = $rev) =~ s/\.0//;
			#	Search the rcs file for all versions on the branch
			my @revlist = ($file =~ m/\n($branchprefix\.\d+)\n/gs);
			if (scalar(@revlist) == 0) {
				# No version found with the prefix,
				# no commit ever on this branch.
				# Keep only the original release number
				$branchprefix =~ s/\.\d+$//;
				@revlist = ($branchprefix);
			}
			# Keep only the latest revision on the branch
			# and replace the branch number
			$rev = $revlist[-1];
			$cvs{'header'}{'symbols'}{$orel} = $rev;
		}

		#	Discard the import branches by nailing them to the root
		#	Import branches have an odd number after 1.1
		#	(from CVS manual).
		if ($rev =~ m/^1\.1\.\d*[13579](\.)?/) {
			if ($1 ne '') {
				$cvs{'header'}{'symbols'}{$orel} = '1.1';
			} else {
				delete $cvs{'header'}{'symbols'}{$orel};
				next;
			}
		}

		#	Next try an user-configurable transformation on symbol
		#	(will be undef if parameter does not exist)
		$nrel = $self->{'config'}->cvsversion($orel);
		next unless defined($nrel);
		if ($nrel ne $orel) {
			delete($cvs{'header'}{'symbols'}{$orel});
			$cvs{'header'}{'symbols'}{$nrel} = $rev if $nrel;
		}
	}

	# Make 'head' look like other symbols
	$cvs{'header'}{'symbols'}{'head'} = $cvs{'header'}{'head'};

	# Explore the other paragraphs until we meet 'desc'.
	# Every paragraph is composed of a revision number (on its own line,
	# but it is not relevant here) followed by an undefined number of
	# attributes.
	while (@cvs && $cvs[0] !~ m/\s*desc\b/s) {
		my ($r, $v) = shift(@cvs) =~ m/\s*(\S+)\s*(.*)/s;
#		                                  1rev1   2--2
#		                                       attributes
		# The attributes are a list of key/value pairs terminated by ;
		# (a value may be empty). When a value needs to contain
		# several "tokens", it is written as an @-string.
		# Since m/.../ extracts two strings each time, it effectively
		# builds a hash pair keyword/value.
		$cvs{'branch'}{$r} = {
			map {	s/@@/@/gs;
					m/^@/s && substr($_, 1, -1) || $_
				# The previous two lines "unquote" the @-strings.
			} $v =~ m/(\w+)\s*((?:[^;@]+|@[^@]*@)*);/gs
#			          +---+   12        2       2 1
#			        keyword   +-------value-------+
		};
	}
	delete $cvs{'branch'}{''};    # somehow an empty branch name gets in; delete it

	# Retrieve the 'desc'ription: either the rest of the line or an @-string
	$cvs{'desc'} = shift(@cvs) =~ /\s*desc\s+((?:[^\n@]+|@[^@]*@)*)\n/s;
#	                                         12         2       2 1
#	                                         +----description-----+
	$cvs{'desc'} =~ s/^@|@($|@)/$1/gs;	# "Unquote" string

}

1;
