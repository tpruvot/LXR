# -*- tab-width: 4 -*-
###############################################
#
# $Id: Mercurial.pm,v 1.5 2013/12/03 13:38:23 ajlittoz Exp $
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

=head1 Mercurial module

This module subclasses the Files module for Mercurial repository.

See Files POD for method information.

Methods are sorted in the same order as in the super-class.

=cut

package LXR::Files::Mercurial;

$CVSID = '$Id: Mercurial.pm,v 1.5 2013/12/03 13:38:23 ajlittoz Exp $ ';

use strict;
use Time::Local;
use LXR::Common;

@LXR::Files::Mercurial::ISA = ('LXR::Files');

our %hg;
our $cache_filename = '';

sub new {
	my ($self, $config) = @_;

	$self = bless({}, $self);
	my $rootpath = substr($config->{'sourceroot'}, 3);
	$rootpath =~ s@/*$@@;
	$self->{'rootpath'} = $rootpath;
	$self->{'hg_blame'} = $config->{'sourceparams'}{'hg_blame'};
	$self->{'hg_annotations'} = $config->{'sourceparams'}{'hg_annotations'}
	# Though Mercurial can provide changeset author independently
	# from annotations, source script design won't work without
	# annotations.
		or $config->{'sourceparams'}{'hg_blame'};
	$self->{'path'} = $config->{'hgpath'};
	my $cmd = 'cd ' . $rootpath
		. ';HGRCPATH=' . $rootpath . '/hg.rc hg ';
	$cmd =~ m/(.*)/;
	$self->{'hg-cmd'} = $1;	# Untaint string
	$self->{'path'} = $config->{'hgpath'};

	return $self;
}

sub getdir {
	my ($self, $pathname, $releaseid) = @_;
	my ($node, @dirs, @files);

	my $hgpath = $pathname;
	$hgpath =~ s,/*$,/,;
	# Paths on the hg command lines must not start with a slash
	# to be relative to 'rootpath'. Changes LXR convention.
	$hgpath =~ s,^/+,,;
	$ENV{'PATH'} = $self->{'path'};
	open(DIR, $$self{'hg-cmd'}
				. "ls-onelevel -r \"$releaseid\" \"$hgpath\" |")
	or die ("hg subprocess died unexpectedly: $!");

	while($node = <DIR>) {
		chomp($node);
		if (substr($node, -1) eq '/') {
			next if $self->_ignoredirs($pathname, substr($node,0,-1));
			push(@dirs, $node)
		} elsif	(!$self->_ignorefiles($pathname, $node)) {
			push(@files, $node)
		}
	}
	closedir(DIR);
	return (sort(@dirs), sort(@files));
}

sub getnextannotation {
	my ($self, $filename, $releaseid) = @_;

	return undef
		unless $self->{'hg_annotations'};

	if (scalar(@{$self->{'annotations'}}) <= 0) {
		$self->loadline();
	}
	return shift @{$self->{'annotations'}};
}

sub getauthor {
	my ($self, $pathname, $releaseid, $rev) = @_;

	return undef
		unless $self->{'hg_blame'};

	if (scalar(@{$self->{'authors'}}) <= 0) {
		$self->loadline();
	}
	return shift @{$self->{'authors'}};
}

#	File designations (release-ids) are restricted to revision
#	numbers (full numerics), tag or branch names.
sub filerev {
	my ($self, $filename, $releaseid) = @_;
	my ($rev, $outrev);

	$ENV{'PATH'} = $self->{'path'};
	$filename =~ s,^/+,,;
	$self->parsehg($filename);
	if ($releaseid !~ m/^\d+$/) {
		$rev = `$$self{'hg-cmd'} id -n -r \"$releaseid\"`;
		if (!defined($rev)) {
		# $releaseid not found: this is an error, but nothing is prepared
		# to handle it; then, return the 'tip' revision.
			$rev = `$$self{'hg-cmd'} id -n -r tip`;
		}
	}

	# First try to get the exact revision
	$rev =~ m/(.*)/;
	$rev = $1;	# Untaint $rev
	$filename =~ m/(.*)/;
	$filename = $1;	# Untaint $filename
	$outrev = `$$self{'hg-cmd'} log -r $rev --template '{rev}' $filename`;
	return $outrev if $outrev ne '';

	# The exact revision was not found
	# Find now the closest revision number (in time)
	# since $releaseid may come from a directory request
	# and a file may not have exactly this revision number
	# in its change set.
	# The heuristics chosen is to retain the revision
	# with the highest time less than or equal to $releaseid.
	# NOTE: will this give correct results?.
	#		Suggestions and contributions are welcome.
	`$$self{'hg-cmd'} log -r $rev --template '{date|hgdate}'`
		=~ m/^(\d+)\s+([+-]?\d+)\s*/;
	my $revtime = $1 + $2;
	$outrev = -1;	# just in case
	foreach my $curtime (sort keys %{$hg{'date2rev'}}) {
		last if $revtime < $curtime;
		if	($outrev < $curtime) {
			$outrev = $curtime;
		}
	}
	if ($outrev != -1) {
		$outrev = $hg{'date2rev'}{$outrev};
	}
	return $outrev;
}

#	getfilehandle returns a handle to a pipe through which the
#	checked out content can be read.
sub getfilehandle {
	my ($self, $filename, $releaseid, $withannot) = @_;
	my $fileh;

	$ENV{'PATH'} = $self->{'path'};
	$filename =~ s,^/+,,;
	$filename =~ m/(.*)/;
	$filename = $1;
	my $rev = $self->filerev($filename, $releaseid);
	$rev =~ m/(.*)/;
	$rev = $1;

	if	(	$withannot
		&&	$self->{'hg_annotations'}
		) {
        my $opt = '-n';
		$opt .= 'u' if $self->{'hg_blame'};
		open ($fileh, $$self{'hg-cmd'}
					. "blame $opt -r $rev \"$filename\" 2>/dev/null |")
		or die("hg subprocess died unexpextedly: $!");
		$self->{'fileh'}       = $fileh;
		$self->{'nextline'}    = undef;
		$self->{'annotations'} = [];
		$self->{'authors'}     = [];
		return $self;
	} else {
		open ($fileh, $$self{'hg-cmd'}
					. "cat -r $rev $filename 2>/dev/null |")
		or die("hg subprocess died unexpextedly: $!");
		return $fileh;
	}
}

sub loadline {
	my ($self) = @_;

	return if !exists $self->{'fileh'};
	my $hgline = $self->{'fileh'}->getline();
	if (!defined($hgline)) {
		close($self->{'fileh'});
		delete $self->{'nextline'};
		delete $self->{'fileh'};
	}
	(my $auth, my $tag, $self->{'nextline'}) =
		$hgline =~
			m/^\s*(\S+)\s+(\d+):\s(.*)/s;
	if ($self->{'hg_annotations'}) {
		push @{$self->{'annotations'}}, $tag;
		push @{$self->{'authors'}}, $auth
			if $self->{'hg_blame'};
	}
}

sub getline {
	my ($self) = @_;

	return undef if !exists $self->{'fileh'};
	if (!defined($self->{'nextline'})) {
		$self->loadline();
	}
	return undef if !exists $self->{'nextline'};
	my $line = $self->{'nextline'};
	$self->{'nextline'} = undef;
	return $line;
}

#	getfilesize returns the file size.
sub getfilesize {
	my ($self, $filename, $releaseid) = @_;

	$filename =~ s,^/+,,;
	$filename =~ m/(.*)/;
	$filename = $1;
	my $rev = $self->filerev($filename, $releaseid);
	$rev =~ m/(.*)/;
	$rev = $1;
	$ENV{'PATH'} = $self->{'path'};
	my $fsize = `$$self{'hg-cmd'} fsize -r $rev $filename`;
	return $fsize;
}

#	getfiletime returns the time and date the file was committed
#	(extracted from control info).
sub getfiletime {
	my ($self, $filename, $releaseid) = @_;

	return undef if $self->isdir($filename, $releaseid);

	$filename =~ s,^/+,,;
	$self->parsehg($filename);
	my $rev = $self->filerev($filename, $releaseid);
	return $hg{'changeset'}{$rev};
}

sub isdir {
	my ($self, $pathname, $releaseid) = @_;

	return substr($pathname, -1, 1) eq '/';
}

sub isfile {
	my ($self, $pathname, $releaseid) = @_;

	return substr($pathname, -1, 1) ne '/';
}


#
#		Private functions
#

=head2 C<alltags ($filename)>

C<alltags> returns a list of all I<tags> available for the designated
file.

=over

=item 1 C<$filename>

A I<string> containing the filename

=back

A I<tag> is not a numeric I<revision>, it is a specific user symbol.
A tag is usually associated with a software release,
but may also name a branching point.

Two files with the same I<release> tag are in a consistent state.

The list is extracted with C<hg tags> command.

=cut

sub alltags {
	my ($self, $filename) = @_;
	my @tags;

	$ENV{'PATH'} = $self->{'path'};
	open(TAGS, $$self{'hg-cmd'}
				. 'tags |')
	or die("hg subprocess died unexpextedly: $!");
	while( <TAGS> ) { 
		m/^(\S+)/;
		push(@tags, $1);
	}
	close(TAGS);
	return sort @tags;
}

=head2 C<allbranches ($filename)>

C<allbranches> returns a list of all I<revisions> available for the designated
file.

=over

=item 1 C<$filename>

A I<string> containing the filename

=back

The list is extracted with C<hg branches> command.

=cut

sub allbranches {
	my ($self, $filename) = @_;
	my @brch;

	$ENV{'PATH'} = $self->{'path'};
	open(BRANCH, $$self{'hg-cmd'}
				. 'branches |')
	or die("hg subprocess died unexpextedly: $!");
	while( <BRANCH> ) { 
		m/^(\S+)/;
		push(@brch, $1);
	}
	close(BRANCH);
	return sort @brch;
}


=head2 C<parsechg ($filename)>

C<parsehg> builds a hash C<%hg> which summarises control information
contained in the Mercurial log for file C<$filename>.

=over

=item 1 C<$filename>

A I<string> containing the filename

=back

C<parsehg> parses a Mercurial log file through the C<hg log> command.

It is critical for good operation of CVS class.

=cut

sub parsehg {
	my ($self, $filename) = @_;
	my @list;

	# Foolproof fence against infinite recursion
	return if $cache_filename eq $filename;
	$cache_filename = $filename;

	undef %hg;

	return if substr($filename, -1, 1) eq '/';	# we can't parse a directory
	$filename =~ s,^/+,,;
	$filename =~ m/(.*)/;
	$filename = $1;
	my $file = '';
	$ENV{'PATH'} = $self->{'path'};
	# This log request with a template retrieves only the LXR-relevant
	# data, i.e. changeset-id and commit time.
	open(HG, $$self{'hg-cmd'}
				. "log --template '{rev} {date|hgdate}\n' $filename |")
	or die("hg subprocess died unexpextedly: $!");
	while (<HG>) {
# 		$file .= $_;	# For "standard" output
		m/^(\d+)\s+(\d+)\s+([+-]?\d+)\s*\n/;
		$hg{'changeset'}{$1} = $2 + $3;
		$hg{'date2rev'}{$2 + $3} = $1;
	}
	close(HG);
}

1;
