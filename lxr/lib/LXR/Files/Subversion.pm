# -*- tab-width: 4 -*-
###############################################
#
# $Id: Subversion.pm,v 1.1 2012/09/21 17:17:08 ajlittoz Exp $
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

$CVSID = '$Id: Subversion.pm,v 1.1 2012/09/21 17:17:08 ajlittoz Exp $ ';

use strict;
use FileHandle;
use LXR::Common;

@LXR::Files::Subversion::ISA = ('LXR::Files');

our $debug = 0;

sub new {
	my ($self, $rootpath, $params) = @_;

	$self = bless({}, $self);
	$rootpath=~ s{/+$}{};
	$self->{'rootpath'} = 'file://' . $rootpath;
	$self->{'svn_blame'} = $$params{'svn_blame'};
	$self->{'svn_annotations'} = $$params{'svn_annotations'};
	if ($self->{'svn_blame'}) {
		# Blame support will only work when commit revisions are available,
		# called annotations here...
		$self->{'svn_annotations'} = 1;
	}

	return $self;
}

sub getdir {
	my ($self, $pathname, $releaseid) = @_;
	my ($node, @dirs, @files, $path);

	if($pathname !~ m!/$!) {
		$pathname = $pathname . '/';
	}

	$path = $self->revpath($pathname, $releaseid);
	$path =~ m/(.*)/;
	$path = $1;	# Untaint path
	open(DIR, "svn list $path |")
	|| die("svn subprocess died unexpextedly: $!");

FILE:
	while($node = <DIR>) { 
		chomp($node);	# Remove trailing newline
		# Skip files starting with a dot (usually invisible),
		# ending with a tilde (editor backup)
		# or having "orig" extension
		next if $node =~ m/^\.|~$|\.orig$/;
		# More may be added if necessary

		# Check directories to ignore
		if ($node =~ m!/$!) {
			foreach my $ignoredir (@{$config->{'ignoredirs'}}) {
				next FILE if $node eq $ignoredir . '/';
			}
			push(@dirs, $node);
		} else {
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
	open(ANNO,"svn blame $uri |")
	|| die("svn subprocess died unexpextedly: $!");
	while( <ANNO> ) { 
		m/\s*(\d+)/;
		push(@revlist, $1);
	}
	close(ANNO);
	return @revlist;
}

sub getauthor {
	my ($self, $filename, $releaseid, $rev) = @_;
	my ($uri, $res);

	return undef unless $self->{'svn_blame'};
	#
	# Note that $rev is a real revision number this time
	# (returned by getannotations() above). This is
	# _not_ a tag name!

	$uri = $self->revpath($filename,$releaseid);
	$uri =~ m/(.*)/;
	$uri = $1;	# Untaint path
	open(LOG,"svn log $uri |")
	|| die("svn subprocess died unexpextedly: $!");
	$res = "unknown";
	while(<LOG>){
		m/^r([\d]+)\s*\|\s*([^\s]+)/;
		if ($1 == $rev) {
			$res = $2;
			last;
		}
	}
	close(LOG);
	return $res;
}

sub filerev {
	my ($self, $filename, $releaseid) = @_;

	if ($releaseid eq 'head') {
		my $path = $self->revpath($filename, $releaseid);
		$path =~ m/(.*)/;
		$path = $1;	# Untaint path
		my $res = `LANGUAGE=en svn info $path|grep 'Last Changed Rev'`;
		$res =~ m/(\d+)/;
		return $1;
	} else {
		$releaseid =~ m/==r(\d+)/;
		return $1;
	}
}

sub getfilehandle {
	my ($self, $filename, $releaseid) = @_;
	my $fileh;

	my $path = $self->revpath($filename, $releaseid);
	$path =~ m/(.*)/;
	$path = $1;	# Untaint path
	# Suppress errors/warnings for following command
	# (mainly, don't flood web-server log with "file doesn't
	# exist" messages).
	# When debugging, it is wise to remove 2>/dev/null.
	open ($fileh, "svn cat $path 2>/dev/null |")
	|| die("svn subprocess died unexpextedly: $!");
	return undef if eof($fileh);
	return $fileh;
}

sub getfilesize {
	my ($self, $filename, $releaseid) = @_;
	my $res;

	my $path = $self->revpath($filename,$releaseid);
	$path =~ m/(.*)/;
	$path = $1;	# Untaint path
	$res = `svn list -v $path`;
	$res =~ m/\s*\d+\s+\w+\s+(?:O\s+)?(\d+)/;
	return $1;
}

sub getfiletime {
	my ($self, $filename, $releaseid) = @_;
	my $res;

	return undef if $filename =~ m!\.\.!;
	my $path = $self->revpath($filename,$releaseid);
	$path =~ m/(.*)/;
	$path = $1;	# Untaint path
	$res = `LANGUAGE=en svn info $path|grep 'Last Changed Date'`;
	$res =~ m/(\d[\d-+ :]+)/;
	$res = $1;
	$res =~ s/\s*$//;
	return $res;
}

sub isdir {
	my ($self, $pathname, $releaseid) = @_;

	my $path = $self->revpath($pathname,$releaseid);
	$path =~ m/(.*)/;
	$path = $1;	# Untaint path
	my $res = `LANGUAGE=en svn info $path 2>/dev/null|grep 'Node Kind'`;
	return $res =~ m!directory!;
}

sub isfile {
	my ($self, $pathname, $releaseid) = @_;

	my $path = $self->revpath($pathname,$releaseid);
	$path =~ m/(.*)/;
	$path = $1;	# Untaint path
	my $res = `LANGUAGE=en svn info $path 2>/dev/null|grep 'Node Kind'`;
	return $res =~ m!file!;
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
		$releaseid = "$1";
		$rev = "-r $2";
	}
	return $self->{'rootpath'} . "/$releaseid$filename $rev";
}

sub allreleases {
	my ($self, $filename) = @_;
	my ($uri, %rel);

	$uri = $self->{'rootpath'} . "/trunk$filename";
	$uri =~ m/(.*)/;
	$uri = $1;	# Untaint path
	open(LOG,"svn log $uri |")
	|| die("svn subprocess died unexpextedly: $!");
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

	$uri = $self->{'rootpath'} . "/branches";
	$uri =~ m/(.*)/;
	$uri = $1;	# Untaint path
	open(BRCH,"svn list $uri |")
	|| die("svn subprocess died unexpextedly: $!");
	while(<BRCH>){
		s!/\n*!!;
		push(@brch, "branches/$_");
	}
	close(BRCH);
	return undef unless @brch;

	foreach my $br (@brch) {
		$uri = $self->{'rootpath'} . "/$br$filename";
		$uri =~ m/(.*)/;
		$uri = $1;	# Untaint path
		open(LOG,"svn log $uri |")
		|| die("svn subprocess died unexpextedly: $!");
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

	$uri = $self->{'rootpath'} . "/tags";
	$uri =~ m/(.*)/;
	$uri = $1;	# Untaint path
	open(TAGS,"svn list $uri |")
	|| die("svn subprocess died unexpextedly: $!");
	while(<TAGS>){
		s!/\n*!!;
		push(@tags, "tags/$_");
	}
	close(TAGS);
	return undef unless @tags;

	foreach my $tag (@tags) {
		$uri = $self->{'rootpath'} . "/$tag$filename";
		$uri =~ m/(.*)/;
		$uri = $1;	# Untaint path
		open(LOG,"svn log $uri |")
		|| die("svn subprocess died unexpextedly: $!");
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
