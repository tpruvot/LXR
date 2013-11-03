# -*- tab-width: 4 -*-
###############################################
#
# $Id: Tagger.pm,v 1.1 2012/09/22 07:49:17 ajlittoz Exp $
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

package Tagger;

$CVSID = '$Id: Tagger.pm,v 1.1 2012/09/22 07:49:17 ajlittoz Exp $ ';

use strict;
use LXR::Lang;
use VTescape;

sub processfile {
	my ($pathname, $releaseid, $config, $files, $index) = @_;

	my $lang = LXR::Lang->new($pathname, $releaseid);
	return undef unless $lang;

	my $revision = $files->filerev($pathname, $releaseid);
	return undef unless $revision;

	(my $filename = $pathname) =~ s!.*/!!;
	print(STDERR "--- $releaseid $filename $revision");

	if ($index) {
		my $fileid = $index->fileid($pathname, $revision);

		$index->setfilerelease($fileid, $releaseid);

		if (!$index->fileindexed($fileid)) {
# 			$index->emptycache();
			print(STDERR " ${VTgreen}$fileid${VTnorm}\n");

			my $path = $files->realfilename($pathname, $releaseid);
			$lang->indexfile($pathname, $path, $fileid, $index, $config);
			$index->setfileindexed($fileid);
			$index->flushcache();
			$index->commit;
			$files->releaserealfilename($path);
		} else {
			print(STDERR " ${VTyellow}already indexed${VTnorm}\n");
		}
	} else {
		print(STDERR " ${VTred}FAILED${VTnorm}\n");
	}
	$lang     = undef;
	$revision = undef;
	return 1;
}

sub processrefs {
	my ($pathname, $releaseid, $config, $files, $index) = @_;

	my $lang = LXR::Lang->new($pathname, $releaseid);
	return undef unless $lang;

	my $revision = $files->filerev($pathname, $releaseid);
	return undef unless $revision;

	(my $filename = $pathname) =~ s!.*/!!;
	print(STDERR "--- $releaseid $filename $revision");

	if ($index) {
		my $fileid = $index->fileid($pathname, $revision);

		if (!$index->filereferenced($fileid)) {
# 			$index->emptycache();
			print(STDERR " ${VTgreen}$fileid${VTnorm} ");

			my $path = $files->realfilename($pathname, $releaseid);
			$lang->referencefile($pathname, $path, $fileid, $index, $config);
			$index->setfilereferenced($fileid);
			$index->flushcache();
			$index->commit;
			$files->releaserealfilename($path);
		} else {
			print(STDERR " ${VTyellow}already referenced${VTnorm}\n");
		}
	} else {
		print(STDERR " ${VTred}FAILED${VTnorm}\n");
	}

	$lang     = undef;
	$revision = undef;
	return 1;
}

1;
