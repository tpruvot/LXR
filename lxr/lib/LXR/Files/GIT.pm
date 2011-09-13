#
# GIT.pm - A file backend for LXR based on GIT.
#
# © 2006 by	Jan-Benedict Glaw <jbglaw@lug-owl.de>
# © 2006 by	Maximilian Wilhelm <max@rfc2324.org>
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
# along with this program; if not, write to the Free Software Foundation
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA
#

package LXR::Files::GIT;

$CVSID = '$Id: GIT.pm,v 1.4 2009/05/10 11:54:29 adrianissott Exp $';

use strict;
use FileHandle;
use Time::Local;
use LXR::Common;
use Git;

sub new {
	my ($self, $rootpath, $params) = @_;

	$self = bless({}, $self);
	$self->{'rootpath'} = $rootpath;
	$self->{'do_blame'} = $$params{'do_blame'};
	$self->{'do_annotations'} = $$params{'do_annotations'};

	if ($self->{'do_blame'}) {
		# Blame support will only work when commit IDs are available,
		# called annotations here...
		$self->{'do_annotations'} = 1;
	}

	return $self;
}

sub isdir {
	my ($self, $pathname, $releaseid) = @_;

	$pathname =~ s/^\///;
	if ($pathname eq "") {
		return 1 == 1;
	} else {
		my $repo = Git->repository (Directory => "$self->{'rootpath'}");
		my $line = $repo->command_oneline ("ls-tree", "$releaseid", "$pathname");
		return $line =~ m/^\d+ tree .*$/;
	}
}

sub isfile {
	my ($self, $pathname, $releaseid) = @_;

	$pathname =~ s/^\///;
	if ($pathname eq "") {
		return 1 == 0;
	} else {
		my $repo = Git->repository (Directory => "$self->{'rootpath'}");
		my $line = $repo->command_oneline ("ls-tree", "$releaseid", "$pathname");
		return $line =~ m/^\d+ blob .*$/;
	}
}

sub getdir {
	my ($self, $pathname, $releaseid) = @_;
	my ($dir, $node, @dirs, @files);
	my $repo = Git->repository (Directory => "$self->{'rootpath'}");

	$pathname =~ s/^\///;

	my ($fh, $c) = $repo->command_output_pipe ("ls-tree", "$releaseid", "$pathname");
	while (<$fh>) {
		if (m/(\d+) (\w+) ([[:xdigit:]]+)\t(.*)/) {
			my ($entrymode, $entrytype, $objectid, $entryname) = ($1, $2, $3, $4);

			# Only get the filename part of the full path
			my @array = split (/\//, $entryname);
			my $num = @array - 1;
			$entryname = @array[$num];

			# Weed out things to ignore
			foreach my $ignoredir ($config->{ignoredirs}) {
				next if $entryname eq $ignoredir;
			}

			next if $entryname =~ /^\.$/;
			next if $entryname =~ /^\.\.$/;

			if ($entrytype eq "blob") {
				push (@files, $entryname);
			} elsif ($entrytype eq "tree") {
				push (@dirs, "$entryname/");
			}
		}
	}

	$repo->command_close_pipe ($fh, $c);

	return sort (@dirs), sort (@files);
}

sub getfilesize {
	my ($self, $filename, $releaseid) = @_;
	my $repo = Git->repository (Directory => "$self->{'rootpath'}");

	$filename =~ s/^\///;

	my $sha1hashline = $repo->command_oneline ("ls-tree", "$releaseid", "$filename");

	if ($sha1hashline =~ m/\d+ blob ([[:xdigit:]]+)\t.*/) {
		return $repo->command_oneline ("cat-file", "-s", "$1");
	}

	return undef;
}

sub tmpfile {
	my ($self, $filename, $releaseid) = @_;
	my ($tmp, $fileh);

	$tmp = $config->tmpdir . '/lxrtmp.' . time . '.' . $$ . '.' . &LXR::Common::tmpcounter;
	open (TMP, "> $tmp") || return undef;
	$fileh = $self->getfilehandle ($filename, $releaseid);
	print (TMP <$fileh>);
	close ($fileh);
	close (TMP);

	return $tmp;
}

sub filerev {
	my ($self, $filename, $releaseid) = @_;
	my $repo = Git->repository (Directory => "$self->{'rootpath'}");

	$filename =~ s/^\///;

	my $sha1hashline = $repo->command_oneline ("ls-tree", "$releaseid", "$filename");

	if ($sha1hashline =~ m/\d+ blob ([[:xdigit:]]+)\t.*/) {
		return $1;
	}

	return undef;
}

sub getfiletime {
	my ($self, $filename, $releaseid) = @_;

	$filename =~ s/^\///;

	if ($filename eq "") {
		return undef;
	}
	if ($filename =~ m/\/$/) {
		return undef;
	}

	my $repo = Git->repository (Directory => "$self->{'rootpath'}");
	my $lastcommitline = $repo->command_oneline ("log", "--max-count=1", "--pretty=oneline", "$releaseid", "--", "$filename");
	if ($lastcommitline =~ m/([[:xdigit:]]+) /) {
		my $commithash = $1;

		my (@fh, $c) = $repo->command ("cat-file", "commit", "$commithash");
		foreach my $line (@fh) {
			if ($line =~ m/^author .* <.*> (\d+) .[0-9]{4}$/) {
				return $1;
			}
		}
		return undef;
	}

	return undef;
}

sub getfilehandle {
	my ($self, $filename, $releaseid) = @_;
	my $repo = Git->repository (Directory => "$self->{'rootpath'}");

	$filename =~ s/^\///;

	my $sha1hashline = $repo->command_oneline ("ls-tree", "$releaseid",  "$filename");

	if ($sha1hashline =~ m/^\d+ blob ([[:xdigit:]]+)\t.*/) {
		my ($fh, $c) = $repo->command_output_pipe ("cat-file", "blob", "$1");
		return $fh;
	}

	return undef;
}

sub getannotations {
	my ($self, $filename, $releaseid) = @_;

	if ($self->{'do_annotations'}) {
		my $repo = Git->repository (Directory => "$self->{'rootpath'}");
		my @revlist = ();
		$filename =~ s/^\///;

		my (@lines, $c) = $repo->command ("blame", "-l", "$releaseid", "--", "$filename");

		foreach my $line (@lines) {
			if ($line =~ m/^([[:xdigit:]]+) .*/) {
				push (@revlist, $1);
			} else {
				push (@revlist, "");
			}
		}

		return @revlist;
	} else {
		return ();
	}
}

sub getauthor {
	my ($self, $pathname, $releaseid) = @_;

	#
	# Note that $releaseid is a real commit this time
	# (returned by getannotations() above). This is
	# _not_ a tag name!
	#

	if ($self->{'do_blame'}) {
		my $repo = Git->repository (Directory => "$self->{'rootpath'}");
		my @authorlist = ();

		$pathname =~ s/^\///;

		my (@lines, $c) = $repo->command ("cat-file", "commit", "$releaseid");
		foreach my $line (@lines) {
			if ($line =~ m/^author (.*) </) {
				return $1
			}
		}

		return undef;
	}

	return undef;
}

1;
