# -*- tab-width: 4 -*-
###############################################
#
# $Id: Plain.pm,v 1.35 2013/11/07 17:58:48 ajlittoz Exp $

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

###############################################

=head1 Plain module

This module subclasses the Files module for plain files repository,
i.e. real files stored in real directories.

See Files POD for method information.

Methods are sorted in the same order as in the super-class.

=cut

package LXR::Files::Plain;

$CVSID = '$Id: Plain.pm,v 1.35 2013/11/07 17:58:48 ajlittoz Exp $ ';

use strict;
use FileHandle;
use LXR::Common;

@LXR::Files::Plain::ISA = ('LXR::Files');

sub new {
	my ($self, $config) = @_;

	$self = bless({}, $self);
	$self->{'rootpath'} = $config->{'sourceroot'};
	# Make sure root directory name ends with a slash
	$self->{'rootpath'} =~ s@/*$@/@;

	return $self;
}

sub getdir {
	my ($self, $pathname, $releaseid) = @_;
	my ($dir, $node, @dirs, @files);

	# Make sure directory name ends with a slash
	if (substr($pathname, -1) ne '/') {
		$pathname = $pathname . '/';
	}
		
	$dir = $self->toreal($pathname, $releaseid);
	opendir(DIR, $dir) || return ();
	while (defined($node = readdir(DIR))) {
		if (-d $dir . $node) {
			next if $self->_ignoredirs($pathname, $node);
			# Keep this directory: suffix name with a slash
			push(@dirs, $node . '/');
		} elsif (!$self->_ignorefiles($pathname, $node)) {
			# Keep this file: don't change the name
			push(@files, $node);
		}
	}
	closedir(DIR);

	return sort(@dirs), sort(@files);
}

#	There are no annotations in real files,
#	just return the empty list
sub getannotations {
	return ();
}
sub getnextannotation {
	return undef;
}

#	No annotations also means no author
sub getauthor {
	return undef;
}

#	No revision either, then return a "signature" made of
#	last modification time (in seconds) followed by file size
sub filerev {
	my ($self, $filename, $releaseid) = @_;

	#	return $releaseid;
	return
	  join	( '-'
			, $self->getfiletime($filename, $releaseid)
			, $self->getfilesize($filename, $releaseid)
			);
}

#	getfilehandle returns a handle to the original real file.
#	Take care not to unlink() it, otherwise it is gone for ever.
sub getfilehandle {
	my ($self, $filename, $releaseid) = @_;

	return FileHandle->new($self->toreal($filename, $releaseid));
}

sub getfilesize {
	my ($self, $filename, $releaseid) = @_;

	return -s $self->toreal($filename, $releaseid);
}

sub getfiletime {
	my ($self, $filename, $releaseid) = @_;

	return (stat($self->toreal($filename, $releaseid)))[9];
}

sub isdir {
	my ($self, $pathname, $releaseid) = @_;

	return -d $self->toreal($pathname, $releaseid);
}

sub isfile {
	my ($self, $pathname, $releaseid) = @_;

	return -f $self->toreal($pathname, $releaseid);
}

=head2 C<realfilename ($pathname, $releaseid)>

C<realfilename> returns the true original name of the file.

=over

=item 1 C<$pathname>

a I<string> containing the path relative to C<'sourceroot'>

=item 1 C<$releaseid>

the release (or version) in which C<$pathname> is expected to
be found

=back

There is a substantial performance advantage in avoiding file copy
into a temporary.
But this is the real file.
Be careful enough not to make destructive operations on it!

B<Note:>

=over

=item

If "standard" file copy is desired, comment out the method
B<AND> C<releaserealfilename>.

=back

=cut

sub realfilename {
	my ($self, $pathname, $releaseid) = @_;

	$self->toreal($pathname, $releaseid) =~ m/(.*)/;
	return $1;	# Untainted name
}

=head2 C<releaserealfilename ($filename)>

C<releaserealfilename> protects againt file erasure.

=over

=item 1 C<$filename>

a I<string> containing the filename

=back

This is the companion "destructor" of C<realfilename>.
Since no file was created, just return for a no-op.

This overrides the default erasure action of the super-class.

=cut

sub releaserealfilename {
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

	return ($self->{'rootpath'} . $releaseid . $pathname);
}

1;
