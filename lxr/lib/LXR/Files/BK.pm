# -*- tab-width: 4 -*- ###############################################
#
# $Id: BK.pm,v 1.6 2012/03/29 18:58:19 ajlittoz Exp $

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

package LXR::Files::BK;

$CVSID = '$Id: BK.pm,v 1.6 2012/03/29 18:58:19 ajlittoz Exp $ ';

use strict;
use File::Spec;
use Cwd;
use IO::File;
use Digest::SHA qw(sha1_hex);
use Time::Local;
use LXR::Common;

use vars qw(%tree_cache @ISA $memcachecount $diskcachecount);

@ISA = ("LXR::Files");
$memcachecount = 0;
$diskcachecount = 0;

sub new {
	my ($self, $rootpath, $params) = @_;

	$self = bless({}, $self);
	$self->{'rootpath'} = $rootpath;
	$self->{'rootpath'} =~ s!/*$!!;
	die "Must specify a cache directory when using BitKeeper" if !(ref($params) eq 'HASH');
	$self->{'cache'} = $$params{'cachepath'};
	return $self;
}

#
# Public interface
#

sub getdir {
	my ($self, $pathname, $releaseid) = @_;

	$self->fill_cache($releaseid);
	$pathname = canonise($pathname);
	$pathname = File::Spec->rootdir() if $pathname eq '';
	my @nodes = keys %{ $tree_cache{$releaseid}->{$pathname} };
	my @dirs = grep m!/$!, @nodes;
	my @files = grep !m!/$!, @nodes;
	return (sort(@dirs), sort(@files));
}

sub getfile {
	my ($self, $pathname, $releaseid) = @_;
	$pathname = canonise($pathname);
	my $fileh = $self->getfilehandle($pathname, $releaseid);

	return undef unless $fileh;
	my $buffer = join('', $fileh->getlines);
	close $fileh;
	return $buffer;
}

sub getfilehandle {
	my ($self, $pathname, $releaseid) = @_;
	$pathname = canonise($pathname);
	my $fileh = undef;
	if ($self->file_exists($pathname, $releaseid)) {
		my $info  = $self->getfileinfo($pathname, $releaseid);
		my $ver   = $info->{'revision'};
		my $where = $info->{'curpath'};
		$fileh = $self->openbkcommand("bk get -p -r$ver $where 2>/dev/null |");
	}
	return $fileh;
}

sub filerev {
	my ($self, $filename, $releaseid) = @_;

	my $info = $self->getfileinfo($filename, $releaseid);
	return sha1_hex($info->{'curpath'} . '-' . $info->{'revision'});
}

sub getfiletime {
	my ($self, $pathname, $releaseid) = @_;

	my $info = $self->getfileinfo($pathname, $releaseid);
	return undef if !defined $info;

	if (!defined($info->{'filetime'})) {
		my $fileh = $self->openbkcommand("bk prs -r$info->{'revision'} -h -d:UTC: $info->{'curpath'} |");
		my $time = <$fileh>;    # Should be a YYYYMMDDHHMMSS string
		close $fileh;
		chomp $time;
		my ($yr, $mth, $day, $hr, $min, $sec) =
		  $time =~ m/(....)(..)(..)(..)(..)(..)/;
		$info->{'filetime'} = timegm($sec, $min, $hr, $day, $mth-1, $yr);
	}

	return $info->{'filetime'};
}

sub getfilesize {
	my ($self, $pathname, $releaseid) = @_;

	my $info = $self->getfileinfo($pathname, $releaseid);
	return undef if !defined($info);

	if (!defined($info->{'filesize'})) {
		$info->{'filesize'} = length($self->getfile($pathname, $releaseid));
	}
	return $info->{'filesize'};
}


sub getauthor {
	my ($self, $pathname, $releaseid) = @_;

	my $info = $self->getfileinfo($pathname, $releaseid);
	return undef if !defined $info;

	if (!defined($info->{'author'})) {
		my $fileh = $self->openbkcommand("bk prs -r$info->{'revision'} -h -d:USER: $info->{'curpath'} |");
		my $user = <$fileh>;
		close $fileh;
		chomp $user;
		$info->{'author'} = $user;
	}

	return $info->{'author'};
}

sub getannotations {
	# No idea what this function should return - Plain.pm returns (), so do that
	return ();
}

sub openbkcommand {
	my ($self, $command) = @_;

	my $dir = getcwd();
	chdir($self->{'rootpath'});
	my $fileh = new IO::File;
	$fileh->open($command) or die "Can't execute $command";
	chdir($dir);
	return $fileh;
}

sub isdir {
	my ($self, $pathname, $releaseid) = @_;
	$self->fill_cache($releaseid);
	$pathname = canonise($pathname);
	my $info = $tree_cache{$releaseid}{$pathname};
	return (defined($info));
}

sub isfile {
	my ($self, $pathname, $releaseid) = @_;
	my $info = $self->getfileinfo($pathname, $releaseid);
	return (defined($info));
}

#	Was tmpfile
sub realfilename {
	my ($self, $filename, $releaseid) = @_;
	my ($tmp,  $buf);

	$buf = $self->getfile($filename, $releaseid);
	return undef unless defined($buf);

	$tmp =
	    $config->tmpdir
	  . '/bktmp.'
	  . time . '.'
	  . $$ . '.'
	  . &LXR::Common::tmpcounter;
	open(TMP, "> $tmp") || return undef;
	print(TMP $buf);
	close(TMP);

	return $tmp;
}

#	Delete temporary file created by realfilename
sub releaserealfilename {
	my ($self, $filename) = @_;

	my $td = $config->{'tmpdir'};
	if ($filename =~ m!^$td/bktmp\.\d+\.\d+\.\d+$!) {
		unlink($filename);
	}
}

#
# Private interface
#

sub insert_entry {
	my ($newtree, $path, $entry, $curfile, $rev) = @_;
	$$newtree{$path} = {} if !defined($$newtree{$path});
	$newtree->{$path}{$entry} = { 'curpath' => $curfile, 'revision' => $rev };
}

sub fill_cache {
	my ($self, $releaseid) = @_;

	return if (defined $tree_cache{$releaseid});

	# Not in cache, so need to build
	my @all_entries = $self->get_tree($releaseid);
	$memcachecount++;

	my %newtree = ();
	my ($entry, $path, $file, $vol, @dirs);
	my ($curfile, $histfile, $rev);
	$newtree{''} = {};

	foreach $entry (@all_entries) {
		($curfile, $histfile, $rev) = split /\|/, $entry;
		($vol, $path, $file) = File::Spec->splitpath($histfile);
		insert_entry(\%newtree, $path, $file, $curfile, $rev);
		while ($path ne File::Spec->rootdir() && $path ne '') {

			# Insert any directories in path into hash
			($vol, $path, $file) =
			  File::Spec->splitpath(
				File::Spec->catdir(File::Spec->splitdir($path)));
			insert_entry(\%newtree, $path, $file . '/');
		}
	}

	# Make / point to ''
	$newtree{ File::Spec->rootdir() } = $newtree{''};
	delete $newtree{''};

	$tree_cache{$releaseid} = \%newtree;
}

sub get_tree {
	my ($self, $releaseid) = @_;

	# Return entire tree as provided by 'bk rset'
	# First, check if cache exists

	my $fileh = new IO::File;

	if (-r $self->cachename($releaseid)) {
		$fileh->open($self->cachename($releaseid)) or die "Whoops, can't open cached version";
	} else {
		# This command provide 3 part output - the current filename, the historical filename & the revision
		$fileh = $self->openbkcommand("bk rset -h -l$releaseid 2>/dev/null |");
		my $line_to_junk = <$fileh>;    # Remove the Changelist|Changelist line at start
		# Now create the cached copy if we can
		if(open(CACHE, ">", $self->cachename($releaseid))) {
			$diskcachecount++;
			my @data = <$fileh>;
			close $fileh;
			print CACHE @data;
			close CACHE;
			$fileh = new IO::File;
			$fileh->open($self->cachename($releaseid)) or die "Couldn't open cached version!";
		}
	}

	my @files = <$fileh>;
	close $fileh;
	chomp @files;

	# remove any BitKeeper metadata except for deleted files
	@files = grep (!(m!^BitKeeper! && !m!^BitKeeper/deleted/!), @files);

	return @files;
}

sub cachename {
	my ($self, $releaseid) = @_;
	return $self->{'cache'}."/treecache-".$releaseid;
}

sub canonise {
	my $path = shift;
	$path =~ s!^/!!;
	return $path;
}

# Check that the specified pathname, version combination exists in repository
sub file_exists {
	my ($self, $pathname, $releaseid) = @_;

	# Look the file up in the treecache
	return defined($self->getfileinfo($pathname, $releaseid));
}

sub getfileinfo {
	my ($self, $pathname, $releaseid) = @_;
	$self->fill_cache($releaseid);    # Normally expect this to be present anyway
	$pathname = canonise($pathname);

	my ($vol, $path, $file) = File::Spec->splitpath($pathname);
	$path = File::Spec->rootdir() if $path eq '';

	return $tree_cache{$releaseid}{$path}{$file};
}

1;
