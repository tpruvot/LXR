# -*- tab-width: 4 -*-
###############################################
#
# $Id: Files.pm,v 1.24 2013/11/07 17:58:48 ajlittoz Exp $

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

=head1 Files module

This module defines the abstract access methods to the files of the
source-tree, independent of the repository format.

=cut

package LXR::Files;

$CVSID = '$Id: Files.pm,v 1.24 2013/11/07 17:58:48 ajlittoz Exp $ ';

use strict;
use LXR::Common;


=head2 C<new ($config)>

C<new> is Files object constructor.
It dispatches to the specific constructor based on its first argument.

=over

=item 1 C<$config>

a I<reference> to the I<hash> containing configuration parameters for this
tree

=over

B<Note:>

=item Perl threads are rather restrictive on the kind of data in
shared variables; it is thus better not to rely on "global" variables
and store a pointer to "global" data inside the object.

=back

=back

=cut

sub new {
	my ( $self, $config ) = @_;
	my $files;

	$config->{'sourceroot'} =~ m/^(\w+):/;
	my $container = uc($1);
	if ('CVS' eq $container) {
		require LXR::Files::CVS;
		$files   = LXR::Files::CVS->new($config);
	}
	elsif ('GIT' eq $container) {
		require LXR::Files::GIT;
		$files   = LXR::Files::GIT->new($config);
	}
	elsif ('SVN' eq $container) {
		require LXR::Files::Subversion;
		$files   = LXR::Files::Subversion->new($config);
	}
	elsif ('HG' eq $container) {
		require LXR::Files::Mercurial;
		$files   = LXR::Files::Mercurial->new($config);
	}
	elsif ('BK' eq $container) {
		require LXR::Files::BK;
		$files   = LXR::Files::BK->new($config);
	}
	else {
		require LXR::Files::Plain;
		$files = LXR::Files::Plain->new($config);
	}
	$files->{'config'} = $config;
	return $files;
}

#
# Stub implementations of this interface
#

=head2 C<getdir ($pathname, $releaseid)>

C<getdir> returns a directory content in an array.

=over

=item 1 C<$pathname>

a I<string> containing the path relative to C<'sourceroot'>

=item 1 C<$releaseid>

the release (or version) in which C<$pathname> is expected to
be found

=back

Function result is C<undef> if directory does not exist in this
version.

=cut

sub getdir {
  my ($self, $pathname, $releaseid) = @_;
  my @dircontents;
	warn  __PACKAGE__."::getdir not implemented. Parameters @_";
	return @dircontents;
}

=head2 C<getfile ($pathname, $releaseid)>

C<getfile> returns a file content in a string.

=over

=item 1 C<$pathname>

a I<string> containing the path relative to C<'sourceroot'>

=item 1 C<$releaseid>

the release (or version) in which C<$pathname> is expected to
be found

=back

Function result is C<undef> if file does not exist in this version.

=cut

# NOTE: This sub is only used by genxref to give a copy of the
#	file to swish-e. Is it really useful?
# -	It is also used by some sub-classes to compute file size
#	when there is no other means to determine it.

sub getfile {
	my ($self, $filename, $releaseid) = @_;

	my $fileh = $self->getfilehandle($filename, $releaseid);
	return undef unless $fileh;
	my $content = join('', $fileh->getlines);
	close ($fileh);
	return $content;
}

=head2 C<getannotations ($pathname, $releaseid)>

C<getannotations> returns the annotations for the designated file.

=over

=item 1 C<$pathname>

a I<string> containing the path relative to C<'sourceroot'>

=item 1 C<$releaseid>

the release (or version) in which C<$pathname> is expected to
be found

=back

An I<annotation> is whatever auxiliary line information kept in
the repository. There is none in plain files. It is the revision
number the line was entered in CVS. It is the release-id in GIT.

Function result is an empty list if there is no annotation or
annotation retrieval is barred by lxr.conf.

B<IMPORTANT NOTICE:>

=over

=item

Starting with release 1.1, this method should only be used for
internal needs of the derived classes because annotation editing
has been drastically changed in script I<source>.

The externally visible method is C<getnextannotation>.

=back

=cut

sub getannotations {
	my ($self, $filename, $releaseid) = @_;
	die  __PACKAGE__."::getannotations deprecated. Parameters @_";
}

=head2 C<getnextannotation ($pathname, $releaseid)>

C<getnextannotation> returns the annotation for the next line
in the designated file.

=over

=item 1 C<$pathname>

a I<string> containing the path relative to C<'sourceroot'>

=item 1 C<$releaseid>

the release (or version) in which C<$pathname> is expected to
be found

=back

An I<annotation> is whatever auxiliary line information kept in
the repository. There is none in plain files. It is the revision
number the line was entered in CVS. It is the release-id in GIT.

Function result is undefined if there is no more annotation or
annotation retrieval is barred by lxr.conf.

=cut

sub getnextannotation {
	my ($self, $filename, $releaseid) = @_;
	warn  __PACKAGE__."::getnextannotation not implemented. Parameters @_";
	my @annotations;
	return @annotations;
}

=head2 C<truncateannotation ($string, $len)>

C<truncateannotation> truncate the annotation and returns the
new length.

=over

=item 1 C<$string>

a I<reference> to a I<string> containing the annotation

=item 1 C<$len>

an I<integer> containing the desired length

=back

The caller must leave room in his layout for an extra character
to be inserted where truncation takes place.
The returned string contains C<$len> + 1 "characters" .
Here, I<character> means a display position on the screen but
may need several bytes to be defined.

This default implementation truncates on left.
It can be overriden in specific classes to truncate on right
or use a different flag character or style.

=cut

sub truncateannotation {
	my ($self, $string, $len) = @_;
	$$string = '<span class="error">&hellip;</span>'
			.	substr($$string, -$len);
	return ++$len;
}

=head2 C<getauthor ($pathname, $releaseid, $annotation)>

C<getauthor> returns the author of the designated revision.

=over

=item 1 C<$pathname>

a I<string> containing the path relative to C<'sourceroot'>

=item 1 C<$releaseid>

the release (or version) in which C<$pathname> is expected to
be found

=item 1 C<$annotation>

the I<annotation> (see sub C<getannotations>) whose author is
looked for

B<Caveat:>

=over

=item

Since VCSs have different ways of identifying file versions,
C<$releaseid> cannot be used.
A prior call to C<getannotations> is needed to associate first
the file and its version.
Next the annotation for the current line is used to get the author.

=back

=back

=cut

sub getauthor {
	my ($self, $filename, $releaseid, $annotation) = @_;
	warn  __PACKAGE__."::getauthor not implemented. Parameters @_";
	my $author;
	return $author;
}

=head2 C<filerev ($pathname, $releaseid)>

C<filerev> returns the latest revision for the file.

=over

=item 1 C<$pathname>

a I<string> containing the path relative to C<'sourceroot'>

=item 1 C<$releaseid>

the release (or version) in which C<$pathname> is expected to
be found

=back

For repositories that do not manage versions (i.e. plain files),
return something making sense, but it does not need to be real.

=cut

sub filerev {
	my ($self, $filename, $releaseid) = @_;
	warn  __PACKAGE__."::filerev not implemented. Parameters @_";
	my $filerev;
	return $filerev;
}

=head2 C<getfilehandle ($pathname, $releaseid)>

C<getfilehandle> returns a handle to the designated file
for further access to the content.

=over

=item 1 C<$pathname>

a I<string> containing the path relative to C<'sourceroot'>

=item 1 C<$releaseid>

the release (or version) in which C<$pathname> is expected to
be found

=back

Returning a file handle may require specific operations with
the repository (check out, file extraction, &hellip;).

=cut

sub getfilehandle {
	my ($self, $filename, $releaseid) = @_;
	warn  __PACKAGE__."::getfilehandle not implemented. Parameters @_";
	my $fh;
	return $fh;
}

=head2 C<getfilesize ($pathname, $releaseid)>

C<getfilesize> returns the file size in bytes.

=over

=item 1 C<$pathname>

a I<string> containing the path relative to C<'sourceroot'>

=item 1 C<$releaseid>

the release (or version) in which C<$pathname> is expected to
be found

=back

For some repositories, this may require extracting the file.

=cut

sub getfilesize {
	my ($self, $filename, $releaseid) = @_;
	warn  __PACKAGE__."::getfilesize not implemented. Parameters @_";
	my $filesize;
	return $filesize;
}

=head2 C<getfiletime ($pathname, $releaseid)>

C<getfiletime> returns the file last modification time.

=over

=item 1 C<$pathname>

a I<string> containing the path relative to C<'sourceroot'>

=item 1 C<$releaseid>

the release (or version) in which C<$pathname> is expected to
be found

=back

For some repositories, this may require extracting the file.

=cut

sub getfiletime {
	my ($self, $filename, $releaseid) = @_;
	warn  __PACKAGE__."::getfiletime not implemented. Parameters @_";
	my $modificationTimeInSecondsSinceEpoch;
	return $modificationTimeInSecondsSinceEpoch;
}

=head2 C<isdir ($pathname, $releaseid)>

C<isdir> returns "true" if the designated path exists and
is a directory.

=over

=item 1 C<$pathname>

a I<string> containing the path relative to C<'sourceroot'>

=item 1 C<$releaseid>

the release (or version) in which C<$pathname> is expected to
be found

=back

Since testing for a directory is rather time-consuming,
arrange to "canonise" paths at the end of httpinit so that
directories always end with C</>. Test will done only once,
eventually adding C</> suffix.
Afterwards, all is needed is test for the trailing slash.

This method is used when the existence must be confirmed, such as
when processing an include link since it is independent from
the currently displayed file.

=cut

sub isdir {
	my ($self, $pathname, $releaseid) = @_;
	warn  __PACKAGE__."::isdir not implemented. Parameters: @_";
	my $boolean;
	return $boolean;
}

=head2 C<isfile ($pathname, $releaseid)>

C<isfile> returns "true" if the designated path exists and
is a file.

=over

=item 1 C<$pathname>

a I<string> containing the path relative to C<'sourceroot'>

=item 1 C<$releaseid>

the release (or version) in which C<$pathname> is expected to
be found

=back

This method is used when the existence must be confirmed, such as
when processing an include link since it is independent from
the currently displayed file.

B<Note:>

=over

=item

I<When the file is subsequently accessed, it is much simpler and
efficient to use C<getfilehandle>, since a handle will be
required anyway.>

=back

=cut

sub isfile {
	my ($self, $pathname, $releaseid) = @_;
	warn  __PACKAGE__."::isfile not implemented. Parameters: @_";
	my $boolean;
	return $boolean;
}

=head2 C<realfilename ($pathname, $releaseid)>

C<realfilename> returns a real filename with the same
content as the designated path (or undef).

=over

=item 1 C<$pathname>

a I<string> containing the path relative to C<'sourceroot'>

=item 1 C<$releaseid>

the release (or version) in which C<$pathname> is expected to
be found

=back

Extract content of the path from repository and stuff it into a
temporary file whose name is returned.

B<Note:>

=over

=item

Override this method if repository is made of plain files
which can be accessed without the copy operation.

=back

=cut

sub realfilename {
	my ($self, $filename, $releaseid) = @_;
	my ($tmp, $fileh);

	$fileh = $self->getfilehandle ($filename, $releaseid);
	return undef unless defined($fileh);

	$tmp = $self->{'config'}{'tmpdir'}
			. '/lxrtmp.'
			. time
			. '.' . $$
			. '.' . &LXR::Common::tmpcounter;
	open (TMP, "> $tmp") || return undef;
	print (TMP <$fileh>);
	close ($fileh);
	close (TMP);

	return $tmp;
}

=head2 C<releaserealfilename ($filename)>

C<releaserealfilename> erases the file created by C<realfilename>.

=over

=item 1 C<$filename>

a I<string> containing the filename

=back

Although some care is exercised to check C<$filename> was created
by C<realfilename>, this test is not fool-proof.
Use this method B<ONLY> against files returned by C<realfilename>.

B<Caveat:>

=over

=item

If you have overridden C<realfilename>, be sure to override also
this method to revert accurately what you have done, otherwise
you risk destroying a valid source-tree file.

=back

=cut

sub releaserealfilename {
	my ($self, $filename) = @_;

	my $td = $self->{'config'}{'tmpdir'};
	if ($filename =~ m!^$td/lxrtmp\.\d+\.\d+\.\d+$!) {
		unlink($filename);
	}
}

=head2 C<_ignoredirs ($path, $node)>

C<_ignoredirs> is an internal (as indicated by _ prefix) filter utility
to exclude directories containing any partial path defined in configuration
parameters C<'ignoredirs'> and C<'filterdirs'>.

=over

=item 1 C<$path>

a I<string> containing the LXR full path for the parent directory

=item 1 C<$node>

a I<string> containing the last directory element

=back

Only the last part is tested for C<'ignoredirs'> since the parent
is supposed to have been scanned by a previous step of the recursive
directory tree traversal.
If a higher element matched one of the C<'ignoredirs'> strings,
that path part was filtered out and no further part is presented to this
function.

C<'filterdirs'> operates on the full path,
I<i.e.> C<$path> concatenated with C<$node>.

B<Note:>

=over

=item

The filter is to be called from C<getdir()>.

I<This usage choice leaves the possibility to override the filter through
manually entering the path in the URL. Since it does not go through
C<getdir()>, the "forbidden" path subdirectory is transmitted unaltered
to the source display script.>

=back

=cut

sub _ignoredirs {
	my ($self, $path, $node) = @_;

	return 1 if substr($node, 0, 1) eq '.';	# ignore "dot" dirs
	foreach my $ignoredir (@{$self->{'config'}{'ignoredirs'}}) {
		return 1 if $node eq $ignoredir;
	}
	foreach my $ignoredir (@{$self->{'config'}{'filterdirs'}}) {
		return 1 if ($path.$node) =~ $ignoredir;
	}
	return 0;
}

=head2 C<_ignorefiles ($path, $node)>

C<_ignorefiles> is an internal (as indicated by _ prefix) filter utility
to exclude files containing patterns defined in configuration
parameters C<'ignorefiles'> and C<'filterfiles'>.

=over

=item 1 C<$path>

a I<string> containing the LXR full path for the parent directory

=item 1 C<$node>

a I<string> containing the file name

=back

Only filename filtering is done for C<'ignorefiles'>,
i.e. the same filter is applied in every directory.
Usually, it screens off "dot" files, editor backups, binaries, ...

C<'filterfiles'> operates on the full path,
I<i.e.> concatenation of the parent directory C<$path>
and the filename C<$node>.

B<Note:>

=over

=item

The filter is to be called from C<getdir()>.

I<This usage choice leaves the possibility to override the filter through
manually entering the path in the URL. Since it does not go through
C<getdir()>, the "forbidden" filename is transmitted unaltered
to the source display script.>

=back

=cut

sub _ignorefiles {
	my ($self, $path, $node) = @_;

	my $ignorepat = $self->{'config'}{'ignorefiles'};
	return 1 if $node =~ m/$ignorepat/;
	foreach my $filterfile (@{$self->{'config'}{'filterfiles'}}) {
		return 1 if ($path.$node) =~ $filterfile;
	}
	return 0;
}

1;
