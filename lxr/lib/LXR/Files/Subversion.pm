# -*- tab-width: 4 -*-
###############################################
#
# $Id: Subversion.pm,v 1.9 2013/12/03 13:38:23 ajlittoz Exp $
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

=head1 Subversion module

This module subclasses the Files module for Subversion repository.

See Files POD for method information.

Methods are sorted in the same order as in the super-class.

=cut

package LXR::Files::Subversion;

$CVSID = '$Id: Subversion.pm,v 1.9 2013/12/03 13:38:23 ajlittoz Exp $ ';

use strict;
use FileHandle;
use Time::Local;
use LXR::Common;

@LXR::Files::Subversion::ISA = ('LXR::Files');

our $debug = 0;

sub new {
	my ($self, $config) = @_;

	$self = bless({}, $self);
	$self->{'rootpath'} = 'file://' . substr($config->{'sourceroot'}, 4);
	$self->{'rootpath'} =~ s{/+$}{};
	$self->{'svn_blame'} = $config->{'sourceparams'}{'svn_blame'};
	$self->{'svn_annotations'} = $config->{'sourceparams'}{'svn_annotations'}
		# Blame support will only work when annotations are available,
		or $config->{'sourceparams'}{'svn_blame'};
	$self->{'path'} = $config->{'svnpath'};
	return $self;
}

sub getdir {
	my ($self, $pathname, $releaseid) = @_;
	my ($node, @dirs, @files, $path);

	if (substr($pathname, -1) ne '/') {
		$pathname = $pathname . '/';
	}

	$path = $self->revpath($pathname, $releaseid);
	$path =~ m/(.*)/;
	$path = $1;	# Untaint path
	$ENV{'PATH'} = $self->{'path'};
	open(DIR, "svn list $path |")
	or die("svn subprocess died unexpextedly: $!");

	while($node = <DIR>) { 
		chomp($node);	# Remove trailing newline
		if ($node =~ m!/$!) {
			next if $self->_ignoredirs($pathname, substr($node,0,-1));
			push(@dirs, $node);
		} elsif (!$self->_ignorefiles($pathname, $node)) {
			push(@files, $node);
		}
	}
	close(DIR);

	return sort(@dirs), sort(@files);
}

sub getannotations {
	my ($self, $filename, $releaseid) = @_;
	my (@revlist, $uri);

	return () unless $self->{'svn_annotations'};

	$uri = $self->revpath($filename,$releaseid);
	$uri =~ m/(.*)/;
	$uri = $1;	# Untaint path
	$ENV{'PATH'} = $self->{'path'};
	open(ANNO,"svn blame $uri |")
	or die("svn subprocess died unexpextedly: $!");
	while( <ANNO> ) { 
		m/\s*(\d+)/;
		push(@revlist, $1);
	}
	close(ANNO);
	return @revlist;
}

sub getnextannotation {
	my ($self, $filename, $releaseid) = @_;

	return undef
		unless $self->{'svn_annotations'};

	if (scalar(@{$self->{'annotations'}}) <= 0) {
		$self->loadline();
	}
	return shift @{$self->{'annotations'}};
}

sub getauthor {
	my ($self, $pathname, $releaseid, $rev) = @_;

	return undef
		unless $self->{'svn_blame'};

	if (scalar(@{$self->{'authors'}}) <= 0) {
		$self->loadline();
	}
	return shift @{$self->{'authors'}};
}

sub filerev {
	my ($self, $filename, $releaseid) = @_;

	if ($releaseid eq 'head') {
		my $path = $self->revpath($filename, $releaseid);
		$path =~ m/(.*)/;
		$path = $1;	# Untaint path
		$ENV{'PATH'} = $self->{'path'};
		my $res = `LANGUAGE=en svn info $path|grep 'Last Changed Rev'`;
		$res =~ m/(\d+)/;
		return $1;
	} else {
		$releaseid =~ m/==r(\d+)/;
		return $1;
	}
}

sub getfilehandle {
	my ($self, $filename, $releaseid, $withannot) = @_;
	my $fileh;

	$ENV{'PATH'} = $self->{'path'};
	my $path = $self->revpath($filename, $releaseid);
	$path =~ m/(.*)/;
	$path = $1;	# Untaint path

	if	(	$withannot
		&&	$self->{'svn_annotations'}
		) {
		open ($fileh, "svn blame $path 2>/dev/null |")
		or die("svn subprocess died unexpextedly: $!");
		return undef if eof($fileh);
		$self->{'fileh'}       = $fileh;
		$self->{'nextline'}    = undef;
		$self->{'annotations'} = [];
		$self->{'authors'}     = [];
		return $self;
	} else {
		# Suppress errors/warnings for following command
		# (mainly, don't flood web-server log with "file doesn't
		# exist" messages).
		# When debugging, it is wise to remove 2>/dev/null.
		open ($fileh, "svn cat $path 2>/dev/null |")
		or die("svn subprocess died unexpextedly: $!");
		return undef if eof($fileh);
		return $fileh;
	}
}

sub loadline {
	my ($self) = @_;

	return if !exists $self->{'fileh'};
	my $svnline = $self->{'fileh'}->getline();
	if (!defined($svnline)) {
		delete $self->{'nextline'};
		delete $self->{'fileh'};
	}
	(my $tag, my $auth, $self->{'nextline'}) =
		$svnline =~
			m/^\s*(\d+)\s+(\S+)\s(.*)/s;
	if ($self->{'svn_annotations'}) {
		push @{$self->{'annotations'}}, $tag;
		push @{$self->{'authors'}}, $auth
			if $self->{'svn_blame'};
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

sub getfilesize {
	my ($self, $filename, $releaseid) = @_;
	my $res;

	my $path = $self->revpath($filename,$releaseid);
	$path =~ m/(.*)/;
	$path = $1;	# Untaint path
	$ENV{'PATH'} = $self->{'path'};
	$res = `svn list -v $path`;
	$res =~ m/\s*\d+\s+\w+\s+(?:O\s+)?(\d+)/;
	return $1;
}

sub getfiletime {
	my ($self, $filename, $releaseid) = @_;
	my ($line, $res);

	return undef if $filename =~ m!\.\.!;
	my $path = $self->revpath($filename,$releaseid);
	$path =~ m/(.*)/;
	$path = $1;	# Untaint path
	$ENV{'PATH'} = $self->{'path'};
	$line = `LANGUAGE=en svn info $path|grep 'Last Changed Date'`;
	$line =~ m/(\d[\d-+ :]+)/;
	$line = $1;
	# Extract local time
	my ($y, $m, $d, $hh, $mm, $ss) = $line =~ m/(....).(..).(..)\s+(..).(..).(..)/;
	# Convert as if an UTC value
	$res = timegm($ss, $mm, $hh, $d, --$m, $y);
	# Get difference between local and UTC time
	($d, $hh, $mm) = $line =~ m/\s+([+-])(..)(..)\s*$/;
	my $delta = ($hh*60 + $mm) * 60;
	# Adjust taking care to invert sign of difference
	if ($d eq '+') {
		$res -= $delta;
	} else {
		$res += $delta;
	}
	return $res;
}

sub isdir {
	my ($self, $pathname, $releaseid) = @_;

	my $path = $self->revpath($pathname,$releaseid);
	$path =~ m/(.*)/;
	$path = $1;	# Untaint path
	$ENV{'PATH'} = $self->{'path'};
	my $res = `LANGUAGE=en svn info $path 2>/dev/null|grep 'Node Kind'`;
	return index($res, 'directory') >= 0;
}

sub isfile {
	my ($self, $pathname, $releaseid) = @_;

	my $path = $self->revpath($pathname,$releaseid);
	$path =~ m/(.*)/;
	$path = $1;	# Untaint path
	$ENV{'PATH'} = $self->{'path'};
	my $res = `LANGUAGE=en svn info $path 2>/dev/null|grep 'Node Kind'`;
	return index($res, 'file') >= 0;
}

#	This is the bridge between Subversion's revision concept
#	and LXR's version concept.
#	NOTE:	it is roughly equivalent to toreal() in the other
#			SCM backends.
#	In subversion, a revision identified by a r[0-9]+ tag can be
#	stored anywhere: in the /trunk line, a /branches ou /tags
#	subdirectory. These two pieces of information must be merged
#	in a single value for variable 'v'.
#	The chosen solution  is to combine the location and revision
#	as string "location==revision".
#	When needed, this string is split at == and location is
#	appended to the root path and revision is added as an -r
#	option for the various svn commands.
#	A special case is "head", meaning the latest revision (default)
#	in the /trunk directory.
sub revpath {
	my ($self, $filename, $releaseid) = @_;
	my $rev;

	if ($releaseid eq 'head') {
		$releaseid = 'trunk';
	} else {
		$releaseid =~ m/(.+)==(.+)/;
		$releaseid = $1;
		$rev = "-r $2";
	}
	return $self->{'rootpath'} . "/$releaseid$filename $rev";
}

sub allreleases {
	my ($self, $filename) = @_;
	my ($uri, %rel);

	$uri = $self->{'rootpath'} . '/trunk' . $filename;
	$uri =~ m/(.*)/;
	$uri = $1;	# Untaint path
	$ENV{'PATH'} = $self->{'path'};
	open(LOG,"svn log $uri |")
	or die("svn subprocess died unexpextedly: $!");
	while(<LOG>){
		if (m/^(r[\d]+)/) {
			$rel{"trunk==$1"} = 1;
		}
	}
	close(LOG);
	$rel{'head'} = 1;	# Add a foolproof revision
	return sort(keys %rel);
}

sub allbranches {
	my ($self, $filename) = @_;
	my ($uri, @brch, %rel);

	$uri = $self->{'rootpath'} . '/branches';
	$uri =~ m/(.*)/;
	$uri = $1;	# Untaint path
	$ENV{'PATH'} = $self->{'path'};
	open(BRCH,"svn list $uri |")
	or die("svn subprocess died unexpextedly: $!");
	while(<BRCH>){
		s!/\n*!!;
		push(@brch, "branches/$_");
	}
	close(BRCH);
	return undef unless @brch;

	foreach my $br (@brch) {
		$uri = $self->{'rootpath'} . '/' . $br . $filename;
		$uri =~ m/(.*)/;
		$uri = $1;	# Untaint path
		open(LOG,"svn log $uri |")
		or die("svn subprocess died unexpextedly: $!");
		while(<LOG>){
			if (m/^(r[\d]+)/) {
				$rel{"$br==$1"} = 1;
			}
		}
		close(LOG);
	}
	return undef unless %rel;
	return sort(keys %rel);
}

sub alltags {
	my ($self, $filename) = @_;
	my ($uri, @tags, %rel);

	$uri = $self->{'rootpath'} . '/tags';
	$uri =~ m/(.*)/;
	$uri = $1;	# Untaint path
	$ENV{'PATH'} = $self->{'path'};
	open(TAGS,"svn list $uri |")
	or die("svn subprocess died unexpextedly: $!");
	while(<TAGS>){
		s!/\n*!!;
		push(@tags, "tags/$_");
	}
	close(TAGS);
	return undef unless @tags;

	foreach my $tag (@tags) {
		$uri = $self->{'rootpath'} . '/' . $tag . $filename;
		$uri =~ m/(.*)/;
		$uri = $1;	# Untaint path
		open(LOG,"svn log $uri |")
		or die("svn subprocess died unexpextedly: $!");
		while(<LOG>){
			if (m/^(r[\d]+)/) {
				$rel{"$tag==$1"} = 1;
			}
		}
		close(LOG);
	}
	return undef unless %rel;
	return sort(keys %rel);
}

1;
