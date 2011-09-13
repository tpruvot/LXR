# -*- tab-width: 4 -*- ###############################################
#
# $Id: Files.pm,v 1.13 2009/05/10 11:54:29 adrianissott Exp $

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

package LXR::Files;

$CVSID = '$Id: Files.pm,v 1.13 2009/05/10 11:54:29 adrianissott Exp $ ';

use strict;

sub new {
	my ( $self, $srcroot, $params ) = @_;
	my $files;

	if ( $srcroot =~ /^CVS:(.*)/i ) {
		require LXR::Files::CVS;
		$srcroot = $1;
		$files   = new LXR::Files::CVS($srcroot);
	}
	elsif ( $srcroot =~ /^bk:(.*)/i ) {
		require LXR::Files::BK;
		$srcroot = $1;
		$files   = new LXR::Files::BK($srcroot, $params);
	}
	elsif ( $srcroot =~ /^git:(.*)/i ) {
		require LXR::Files::GIT;
		$srcroot = $1;
		$files   = new LXR::Files::GIT($srcroot, $params);
	}
	else {
		require LXR::Files::Plain;
		$files = new LXR::Files::Plain($srcroot);
	}
	return $files;
}

#
# Stub implementations of this interface
#

sub getdir {
  my ($self, $pathname, $releaseid) = @_;
  my @dircontents;
	warn  __PACKAGE__."::getdir not implemented. Parameters @_";
	return @dircontents;
}

sub getfile {
	my ($self, $pathname, $releaseid) = @_;
	warn  __PACKAGE__."::getfile not implemented. Parameters @_";
	my $filecontents;
	return $filecontents;
}

sub getannotations {
	my ($self, $filename, $releaseid) = @_;
	warn  __PACKAGE__."::getannotations not implemented. Parameters @_";
	my @annotations;
	return @annotations;
}

sub getauthor {
	my ($self, $filename, $revision) = @_;
	warn  __PACKAGE__."::getauthor not implemented. Parameters @_";
	my $author;
	return $author;
}

sub filerev {
	my ($self, $filename, $releaseid) = @_;
	warn  __PACKAGE__."::filerev not implemented. Parameters @_";
	my $filerev;
	return $filerev;
}

sub getfilehandle {
	my ($self, $filename, $releaseid) = @_;
	warn  __PACKAGE__."::getfilehandle not implemented. Parameters @_";
	my $fh;
	return $fh;
}

sub getfilesize {
	my ($self, $filename, $releaseid) = @_;
	warn  __PACKAGE__."::getfilesize not implemented. Parameters @_";
	my $filesize;
	return $filesize;
}

sub getfiletime {
	my ($self, $filename, $releaseid) = @_;
	warn  __PACKAGE__."::getfiletime not implemented. Parameters @_";
	my $modificationTimeInSecondsSinceEpoch;
	return $modificationTimeInSecondsSinceEpoch;
}

sub getindex {
	my ($self, $pathname, $releaseid) = @_;
	warn  __PACKAGE__."::getindex not implemented. Parameters @_";
	my %index;
	return %index;
}

sub isdir {
	my ($self, $pathname, $releaseid) = @_;
	warn  __PACKAGE__."::isdir not implemented. Parameters: @_";
	my $boolean;
	return $boolean;
}

sub isfile {
	my ($self, $pathname, $releaseid) = @_;
	warn  __PACKAGE__."::isfile not implemented. Parameters: @_";
	my $boolean;
	return $boolean;
}

# FIXME: This function really sucks and should be removed :)
sub tmpfile {
	my ($self, $filename, $releaseid) = @_;
	warn  __PACKAGE__."::tmpfile not implemented. Parameters: @_";
	my $pathToATmpCopyOfTheFile;
	return $pathToATmpCopyOfTheFile;
}

# FIXME: this function should probably not exist, since it doesn't make sense for 
# all file access methods
sub toreal {
  my ($self, $pathname, $releaseid) = @_;
	warn "toreal called - obsolete";
	my $path;
	return $path;
}

1;
