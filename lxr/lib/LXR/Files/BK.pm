# -*- tab-width: 4 -*-
###############################################
#
# $Id: BK.pm,v 1.13 2013/12/03 13:38:23 ajlittoz Exp $

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

=head1 BK module

This module subclasses the Files module for BitKeeper repository.

See Files POD for method information.

Methods are sorted in the same order as in the super-class.

B<Caveat:>

=over

=item

As BitKeeper is proprietary software since 2005, this package is
in the state it reached at that date, apart from commenting,
sorting the methods to match Files.pm order, removal of C<getfile>
(which is abstract enough to be coded in the super class).

=back

Andre J. Littoz - April 2012

=cut

package LXR::Files::BK;

$CVSID = '$Id: BK.pm,v 1.13 2013/12/03 13:38:23 ajlittoz Exp $ ';

use strict;
use File::Spec;
use Cwd;
use IO::File;
use Digest::SHA qw(sha1_hex);
use Time::Local;
use LXR::Common;

@LXR::Files::BK::ISA = ('LXR::Files');

our %tree_cache;
our $memcachecount = 0;
our $diskcachecount = 0;

sub new {
	my ($self, $config) = @_;

	$self = bless({}, $self);
	$self->{'rootpath'} = substr($config->{'sourceroot'}, 3);
	$self->{'rootpath'} =~ s!/*$!!;
	$self->{'path'} = $config->{'cvspath'};
	die 'Must specify a cache directory when using BitKeeper' if !(ref($params) eq 'HASH');
	$self->{'cache'} = $config->{'sourceparams'}{'cachepath'};
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
# TODO: check this blind feature port
	@dirs = grep {
		my ($path, $node) = $_ =~ m!(.*/)([^/]+)/$!;
		!$self->_ignoredirs($path, $node);
			} @dirs;
	my @files = grep !m!/$!, @nodes;
	@files = grep {
		my ($path, $node) = $_ =~ m!(.*/)([^/]+)$!;
		!$self->_ignorefiles($path, $node);
			} @files;
	return (sort(@dirs), sort(@files));
}

sub getannotations {
	# No idea what this function should return - Plain.pm returns (), so do that
	return ();
}
sub getnextannotation {
	# No idea what this function should return - Plain.pm returns undef, so do that
	return undef;
}

sub getauthor {
	my ($self, $pathname, $releaseid, $revision) = @_;

	my $info = $self->getfileinfo($pathname, $revision);
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

sub filerev {
	my ($self, $filename, $releaseid) = @_;

	my $info = $self->getfileinfo($filename, $releaseid);
	return sha1_hex($info->{'curpath'} . '-' . $info->{'revision'});
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

sub getfilesize {
	my ($self, $pathname, $releaseid) = @_;

	my $info = $self->getfileinfo($pathname, $releaseid);
	return undef if !defined($info);

	if (!defined($info->{'filesize'})) {
		$info->{'filesize'} = length($self->getfile($pathname, $releaseid));
	}
	return $info->{'filesize'};
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


#
# Private interface
#

sub openbkcommand {
	my ($self, $command) = @_;

	my $dir = getcwd();
	chdir($self->{'rootpath'});
	my $fileh = IO::File->new();
	$ENV{'PATH'} = $self->{'path'};
	$fileh->open($command) or die "Can't execute $command";
	chdir($dir);
	return $fileh;
}

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

	my $fileh = IO::File->new();

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
			$fileh = IO::File->new();
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
	return $self->{'cache'}.'/treecache-'.$releaseid;
}

sub canonise {
	my $path = shift;
	return substr($path, 1);
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
