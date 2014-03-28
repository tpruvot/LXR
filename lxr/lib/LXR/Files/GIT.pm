# -*- tab-width: 4 -*-
###############################################
#
# GIT.pm - A file backend for LXR based on GIT.
#
# $Id: GIT.pm,v 1.17 2013/12/03 13:38:23 ajlittoz Exp $
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
###############################################

=head1 GIT module

This module subclasses the Files module for Git repository.

See Files POD for method information.

Methods are sorted in the same order as in the super-class.

B<Note:>

=over

=item

GIT.pm was initially based on library Git.pm module.
Unhappily, it systematically errored out with I<"Insecure
dependency in &hellip;"> and was unusable.

Since it was inconvenient to chase all occurrences of arguments
to untaint them, it was considered easier to rewrite an interface
method to git commands and untaint there.

It is likely that it is less versatile and clean than the library
module, but at least it works for LXR.

=back

=cut

package LXR::Files::GIT;

$CVSID = '$Id: GIT.pm,v 1.17 2013/12/03 13:38:23 ajlittoz Exp $';

use strict;
use Time::Local;
use Scalar::Util;
use LXR::Common;

@LXR::Files::GIT::ISA = ('LXR::Files');

sub new {
	my ($self, $config) = @_;

	$self = bless({}, $self);
	$self->{'rootpath'} = substr($config->{'sourceroot'}, 4);
	$self->{'git_blame'} = $config->{'sourceparams'}{'git_blame'};
	$self->{'git_annotations'} = $config->{'sourceparams'}{'git_annotations'}
			|| $config->{'sourceparams'}{'git_blame'};
		# Blame support will only work when commit IDs are available,
		# called annotations here...
	$self->{'path'} = $config->{'gitpath'};
	return $self;
}

sub getdir {
	my ($self, $pathname, $releaseid) = @_;
	my ($dir, @dirs, @files);

	# Paths on the git command lines must not start with a slash
	# to be relative to 'rootpath'. Changes LXR convention.
	$pathname =~ s,^/+,,;

	my $git;
	# Can't just use the empty pathname for the root directory:
	# an empty string confuses ls-tree; we must ensure there
	# really is NO argument in this case.
	if ($pathname eq '') {
		$git = $self->_git_cmd ('ls-tree', $releaseid);
	} else {
		$git = $self->_git_cmd ('ls-tree', $releaseid, '--', $pathname);
	}
	while (<$git>) {
		if (m/(\d+) (\w+) ([[:xdigit:]]+)\t(.*)/) {
			my ($entrymode, $entrytype, $objectid, $entryname) = ($1, $2, $3, $4);

			# Only keep the filename part of the full path
			$entryname =~ s!^.*/!!;

			if ($entrytype eq 'tree') {
				next if $self->_ignoredirs($pathname, $entryname);
				push (@dirs, $entryname . '/');
			} elsif	(	$entrytype eq 'blob'
					&&	!$self->_ignorefiles($pathname, $entryname)
					) {
				push (@files, $entryname);
			}
		}
	}
	close ($git);

	return sort (@dirs), sort (@files);
}

sub getnextannotation {
	my ($self, $filename, $releaseid) = @_;

	return undef
		unless $self->{'git_annotations'};

	if (scalar(@{$self->{'annotations'}}) <= 0) {
		$self->loadline();
	}
	return shift @{$self->{'annotations'}};
}

sub truncateannotation {
	my ($self, $string, $len) = @_;
	$$string = substr($$string, 0, $len)
			.	'<span class="error">&hellip;</span>';
	return ++$len;
}

sub getauthor {
	my ($self, $pathname, $releaseid, $rev) = @_;

	return undef
		unless $self->{'git_blame'};

	if (scalar(@{$self->{'authors'}}) <= 0) {
		$self->loadline();
	}
	return shift @{$self->{'authors'}};
}

#	To be consistent with the other Files classes, returns the first
#	SHA1 hash for the file (it should be the last revision one).
#	This allows to mark the lastly added lines too.
#	If there were not this requirement, the blob SHA1 could do,
#	sparing the call for rev-list.
sub filerev {
	my ($self, $filename, $releaseid) = @_;

	# Paths on the git command lines must not start with a slash
	# to be relative to 'rootpath'. Changes LXR convention.
	$filename =~ s,^/+,,;

	my $sha1hashline = $self->_git_oneline ('ls-tree', $releaseid, '--', $filename);
	if ($sha1hashline =~ m/\d+ blob ([[:xdigit:]]+)\t.*/) {
		return substr	($self->_git_oneline
							('rev-list'
							, '-n', '1'
	# WARNING: 8 is the default abbreviated SHA1 length implied
	#			by option -c in getfilehandle. Update this value
	#			if git uses a different default length.
							, '--abbrev-commit'
							, '--abbrev=8'
							, $releaseid
							, '--'
							, $filename
							)
						,0,-1);
	}

	return undef;
}

sub getfilehandle {
	my ($self, $filename, $releaseid, $withannot) = @_;

	# Paths on the git command lines must not start with a slash
	# to be relative to 'rootpath'. Changes LXR convention.
	$filename =~ s,^/+,,;

	if	(	$withannot
		&&	$self->{'git_annotations'}
		) {
		$self->{'fileh'} = $self->_git_cmd
								( 'blame'
								, '-tc'
								, $releaseid
								, '--'
								, $filename
								);
		$self->{'nextline'}    = undef;
		$self->{'annotations'} = [];
		$self->{'authors'}     = [];
		return $self;
	} else {
		my $sha1hashline = $self->_git_oneline ('ls-tree', $releaseid, '--', $filename);
		if ($sha1hashline =~ m/^\d+ blob ([[:xdigit:]]+)\t.*/) {
			my $fh = $self->_git_cmd ('cat-file', 'blob', $1);
			die('Error executing "git cat-file"') unless $fh;
			return $fh;
		}
	}

	return undef;
}

sub loadline {
	my ($self) = @_;

	return if !exists $self->{'fileh'};
	my $gitline = $self->{'fileh'}->getline();
	if (!defined($gitline)) {
		close($self->{'fileh'});
		delete $self->{'nextline'};
		delete $self->{'fileh'};
	}
	(my $tag, my $auth, $self->{'nextline'}) =
		$gitline =~
			m/^([[:xdigit:]]+)\s+\(\s*(.+)\s+\d+\s+[+-]?\d+\s+\d+\)(.*)/s;
			#  +---- tag ----+        auth                         line
	if ($self->{'git_annotations'}) {
		push @{$self->{'annotations'}}, $tag;
		push @{$self->{'authors'}}, $auth
			if $self->{'git_blame'};
	}
}

sub getline {
	my ($self) = @_;

	return undef if !exists $self->{'fileh'};
	if (!defined($self->{'nextline'})) {
		$self->loadline();
	}
	return undef if !exists $self->{'nextline'};
	my $line = $self->{'nextline'};
	$self->{'nextline'} = undef;
	return $line;
}

sub getfilesize {
	my ($self, $filename, $releaseid) = @_;

	# Paths on the git command lines must not start with a slash
	# to be relative to 'rootpath'. Changes LXR convention.
	$filename =~ s,^/+,,;

	my $sha1hashline = $self->_git_oneline ('ls-tree', $releaseid, '--', $filename);
	if ($sha1hashline =~ m/\d+ blob ([[:xdigit:]]+)\t.*/) {
		return $self->_git_oneline ('cat-file', '-s', $1);
	}

	return undef;
}

#	getfiletime returns the time and date the file was committed
#	(with cat-file commit).
sub getfiletime {
	my ($self, $filename, $releaseid) = @_;

	# Paths on the git command lines must not start with a slash
	# to be relative to 'rootpath'. Changes LXR convention.
	$filename =~ s,^/+,,;

	if ($filename eq '') {
		return undef;
	}
	if ($filename =~ m/\/$/) {
		return undef;
	}

	my $lastcommitline = $self->_git_oneline
									( 'log'
									, '--max-count=1'
									, '--pretty=oneline'
									, $releaseid
									, '--'
									, $filename
									);
	if ($lastcommitline =~ m/([[:xdigit:]]+) /) {
		my $commithash = $1;

		my $git = $self->_git_cmd ('cat-file', 'commit', $commithash);
		while (<$git>) {
			if (m/^author .* <.*> (\d+) .[0-9]{4}$/) {
				close ($git);
				return $1;
			}
		}
		close ($git);
		return undef;
	}

	return undef;
}

sub isdir {
	my ($self, $pathname, $releaseid) = @_;

	# Paths on the git command lines must not start with a slash
	# to be relative to 'rootpath'. Changes LXR convention.
	$pathname =~ s,^/+,,;
	if ($pathname eq '') {
		return 1 == 1;
	} else {
		my $line = $self->_git_oneline ('ls-tree', $releaseid, '--', $pathname);
		return $line =~ m/^\d+ tree .*$/;
	}
}

sub isfile {
	my ($self, $pathname, $releaseid) = @_;

	# Paths on the git command lines must not start with a slash
	# to be relative to 'rootpath'. Changes LXR convention.
	$pathname =~ s,^/+,,;
	if ($pathname eq '') {
		return 1 == 0;
	} else {
		my $line = $self->_git_oneline ('ls-tree', $releaseid, '--', $pathname);
		return $line =~ m/^\d+ blob .*$/;
	}
}


#
#		Private functions
#

=head2 C<_git_cmd ($cmd, @args)>

C<_git_cmd> returns a handle to a pipe where the command outputs its result.

=over

=item 1 C<$cmd>

a I<string> containing the Git command

=item 1 C<@args>

a I<list> containing the command arguments

=back

The command is processed after untainting the arguments.

=cut

sub _git_cmd {
	my ($self, $cmd, @args) = @_;

	#	Blindly untaint all arguments to git command
	#	otherwise we get the infamous "Insecure dependency ..." error
	#	message. The insecure reference is in the file names
	#	which are obtained from the URL.
	#	NOTE: There may be a security hole here !
	my @clean;
	foreach (@args) {
		m/^(.+)$/;
		push (@clean, $1);
	}
	my $git;
	$! = '';
	$ENV{'PATH'} = $self->{'path'};
	open	( $git
			, '-|'
			, 'git'
			, '--git-dir='.$$self{'rootpath'}
			, $cmd
			, @clean
			)
	or die "git subprocess died unexpextedly: $!\n";
	return $git;
}

=head2 C<_git_oneline ($cmd, @args)>

C<_git_oneline> is a wrapper function for C<_git-cmd> when a single line
result is expected.

=over

=item 1 C<$cmd>

a I<string> containing the Git command

=item 1 C<@args>

a I<list> containing the command arguments

=back

The function passes its arguments to C<_git_cmd> and closes the pipe after
reading one line.
This line is returned as a string.

B<Note:>

=over

=item

Pipe is closed before returning BUT close status is not checked
despite all warnings in perldoc. It is expected that the
result line will be empty or undefined if something goes
wrong with the pipe.

=back

=cut

sub _git_oneline {
	my ($self, $cmd, @args) = @_;

	my $git = $self->_git_cmd ($cmd, @args);
	my $line = <$git>;
	close ($git);
	return $line;
}

1;
