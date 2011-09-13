# -*- tab-width: 4 -*- ###############################################
#
# $Id: Tagger.pm,v 1.25 2009/05/10 11:54:29 adrianissott Exp $

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

package LXR::Tagger;

$CVSID = '$Id: Tagger.pm,v 1.25 2009/05/10 11:54:29 adrianissott Exp $ ';

use strict;
use FileHandle;
use LXR::Lang;

sub processfile {
	my ($pathname, $releaseid, $config, $files, $index) = @_;

	my $lang = new LXR::Lang($pathname, $releaseid);

	return unless $lang;

	my $revision = $files->filerev($pathname, $releaseid);

	return unless $revision;

	print(STDERR "--- $pathname $releaseid $revision\n");

	if ($index) {
		my $fileid = $index->fileid($pathname, $revision);

		$index->setfilerelease($fileid, $releaseid);

		if (!$index->fileindexed($fileid)) {
			$index->emptycache();
			print(STDERR "--- $pathname $fileid\n");

			my $path = $files->tmpfile($pathname, $releaseid);

			$lang->indexfile($pathname, $path, $fileid, $index, $config);
			$index->setfileindexed($fileid);
			unlink($path);
		} else {
			print(STDERR "$pathname was already indexed\n");
		}
	} else {
		print(STDERR " **** FAILED ****\n");
	}
	$lang     = undef;
	$revision = undef;
}

sub processrefs {
	my ($pathname, $releaseid, $config, $files, $index) = @_;

	my $lang = new LXR::Lang($pathname, $releaseid);

	return unless $lang;

	my $revision = $files->filerev($pathname, $releaseid);

	return unless $revision;

	print(STDERR "--- $pathname $releaseid $revision\n");

	if ($index) {
		my $fileid = $index->fileid($pathname, $revision);

		if (!$index->filereferenced($fileid)) {
			$index->emptycache();
			print(STDERR "--- $pathname $fileid\n");

			my $path = $files->tmpfile($pathname, $releaseid);

			$lang->referencefile($pathname, $path, $fileid, $index, $config);
			$index->setfilereferenced($fileid);
			unlink($path);
		} else {
			print STDERR "$pathname was already referenced\n";
		}
	} else {
		print(STDERR " **** FAILED ****\n");
	}

	$lang     = undef;
	$revision = undef;
}

1;
