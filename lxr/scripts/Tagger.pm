# -*- tab-width: 4 -*-
###############################################
#
# $Id: Tagger.pm,v 1.3 2013/11/17 15:57:42 ajlittoz Exp $
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

$CVSID = '$Id: Tagger.pm,v 1.3 2013/11/17 15:57:42 ajlittoz Exp $ ';

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
			print(STDERR " ${VTgreen}$fileid${VTnorm}");

			my $path = $files->realfilename($pathname, $releaseid);
			if (defined($path)) {
				my $ns = $lang->indexfile($pathname, $path, $fileid, $index, $config);
				print(STDERR ' :: ', $ns, "\n");
				$index->flushcache(0);
				$index->setfileindexed($fileid);
### The following line is commented out to improve performance.
### The consequence is a higher load on memory since DB updates
### are kept in memory until commit time (at least on directory
### exit).
# 				$index->commit();
### This line is ABSOLUTELY mandatory in case multi-thread is publicly released
			} else {
				print(STDERR " ${VTred}FAILED${VTnorm}\n");
			}
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
			print(STDERR " ${VTgreen}$fileid${VTnorm} ");

			my $path = $files->realfilename($pathname, $releaseid);
			if	(defined($path)) {
				my ($ln, $ns) = $lang->referencefile
							( $pathname
							, $path
							, $fileid
							, $index
							, $config
							);
				if (0 > $ln) {
					# This happens sometimes in CVS
					print(STDERR " ${VTred}### FAILED${VTnorm}\n");
				} else {
					print(STDERR "+++ $ln/$ns\n");
				}
				$index->flushcache(0);
				$index->setfilereferenced($fileid);
### The following line is commented out to improve performance.
### The consequence is a higher load on memory since DB updates
### are kept in memory until commit time (at least on directory
### exit).
# 				$index->commit();
### This line is ABSOLUTELY mandatory in case multi-thread is publicly released
			} else {
				print(STDERR " ${VTred}FAILED${VTnorm}\n");
			}
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
