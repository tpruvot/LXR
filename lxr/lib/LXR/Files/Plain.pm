# -*- tab-width: 4 -*- ###############################################
#
# $Id: Plain.pm,v 1.28 2012/04/02 19:20:39 ajlittoz Exp $

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

package LXR::Files::Plain;

$CVSID = '$Id: Plain.pm,v 1.28 2012/04/02 19:20:39 ajlittoz Exp $ ';

use strict;
use FileHandle;
use LXR::Common;

sub new {
	my ($self, $rootpath) = @_;

	$self = bless({}, $self);
	$self->{'rootpath'} = $rootpath;
	$self->{'rootpath'} =~ s@/*$@/@;

	return $self;
}

sub filerev {
	my ($self, $filename, $releaseid) = @_;

	#	return $releaseid;
	return
	  join("-", $self->getfiletime($filename, $releaseid), $self->getfilesize($filename, $releaseid));
}

sub getfiletime {
	my ($self, $filename, $releaseid) = @_;

	return (stat($self->toreal($filename, $releaseid)))[9];
}

sub getfilesize {
	my ($self, $filename, $releaseid) = @_;

	return -s $self->toreal($filename, $releaseid);
}

sub getfile {
	my ($self, $filename, $releaseid) = @_;
	my ($buffer);
	local ($/) = undef;

	open(FILE, "<", $self->toreal($filename, $releaseid)) || return undef;
	$buffer = <FILE>;
	close(FILE);
	return $buffer;
}

sub getfilehandle {
	my ($self, $filename, $releaseid) = @_;
	my ($fileh);

	$fileh = new FileHandle($self->toreal($filename, $releaseid));
	return $fileh;
}

sub tmpfile {
	my ($self, $filename, $releaseid) = @_;
	my ($tmp, $tries);
	local ($/) = undef;

	$tmp = $config->tmpdir . '/lxrtmp.' . time . '.' . $$ . '.' . &LXR::Common::tmpcounter;
	open(TMP, "> $tmp") || return undef;
	open(FILE, "<", $self->toreal($filename, $releaseid)) || return undef;
	print(TMP <FILE>);
	close(FILE);
	close(TMP);

	return $tmp;
}

sub getannotations {
	return ();
}

sub getauthor {
	return undef;
}

sub getdir {
	my ($self, $pathname, $releaseid) = @_;
	my ($dir, $node, @dirs, @files);

	if($pathname !~ m!/$!) {
		$pathname = $pathname . '/';
	}
		
	$dir = $self->toreal($pathname, $releaseid);
	opendir(DIR, $dir) || return ();
  FILE: while (defined($node = readdir(DIR))) {
		next if $node =~ /^\.|~$|\.orig$/;
		next if $node eq 'CVS';

		if (-d $dir . $node) {
			foreach my $ignoredir ($config->ignoredirs) {
				next FILE if $node eq $ignoredir;
			}
			push(@dirs, $node . '/');
		} else {
			push(@files, $node);
		}
	}
	closedir(DIR);

	return sort(@dirs), sort(@files);
}

# This function should not be used outside this module
# except for printing error messages
# (I'm not sure even that is legitimate use, considering
# other possible File classes.)

sub toreal {
	my ($self, $pathname, $releaseid) = @_;

# nearly all (if not all) method calls eventually call toreal(), so this is a good place to block file access
	foreach my $ignoredir ($config->ignoredirs) {
		return undef if $pathname =~ m|/$ignoredir/|;
	}
	if (!defined $releaseid) {
		$releaseid="";
	}

	return ($self->{'rootpath'} . $releaseid . $pathname);
}

sub isdir {
	my ($self, $pathname, $releaseid) = @_;

	return -d $self->toreal($pathname, $releaseid);
}

sub isfile {
	my ($self, $pathname, $releaseid) = @_;

	return -f $self->toreal($pathname, $releaseid);
}

sub realfilename {
	my ($self, $pathname, $releaseid) = @_;

	$self->toreal($pathname, $releaseid) =~ m/(.*)/;
	return $1;	# Untainted name
}

#	Nothing was allocated by realfilename, just return
sub releaserealfilename {
}

sub getindex {
	my ($self, $pathname, $releaseid) = @_;
	my ($index, %index);
	my $indexname = $self->toreal($pathname, $releaseid) . "00-INDEX";

	if (-f $indexname) {
		open(INDEX, "<", $indexname)
		  || warning("Existing $indexname could not be opened.");
		local ($/) = undef;
		$index = <INDEX>;

		%index = $index =~ /\n(\S*)\s*\n\t-\s*([^\n]*)/gs;
	}
	return %index;
}

1;
