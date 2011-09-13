# -*- tab-width: 4 -*- ###############################################
#
# $Id: CVS.pm,v 1.36 2009/05/10 11:54:29 adrianissott Exp $

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

package LXR::Files::CVS;

$CVSID = '$Id: CVS.pm,v 1.36 2009/05/10 11:54:29 adrianissott Exp $ ';

use strict;
use FileHandle;
use Time::Local;
use LXR::Common;

use vars qw(%cvs $cache_filename $gnu_diff);

$cache_filename = '';

sub new {
	my ($self, $rootpath) = @_;

	$self = bless({}, $self);
	$self->{'rootpath'} = $rootpath;
	$self->{'rootpath'} =~ s@/*$@/@;
	$self->{'path'} = $config->cvspath;
	
	unless (defined $gnu_diff) {

		# the rcsdiff command (used in getdiff) uses parameters only supported by GNU diff
		$ENV{'PATH'} = $self->{'path'};
		if (`diff --version 2>/dev/null` =~ /GNU/) {
			$gnu_diff = 1;
		} else {
			$gnu_diff = 0;
		}
	}

	return $self;
}

sub filerev {
	my ($self, $filename, $releaseid) = @_;

	if ($releaseid =~ /rev_([\d\.]+)/) {
		return $1;
	} elsif ($releaseid =~ /^([\d\.]+)$/) {
		return $1;
	} else {
		$self->parsecvs($filename);
		return $cvs{'header'}{'symbols'}{$releaseid};
	}
}

sub getfiletime {
	my ($self, $filename, $releaseid) = @_;

	return undef if $self->isdir($filename, $releaseid);

	$self->parsecvs($filename);

	my $rev = $self->filerev($filename, $releaseid);

	return undef unless defined($rev);

	my @t = reverse(split(/\./, $cvs{'branch'}{$rev}{'date'}));

	return undef unless @t;

	$t[4]--;
	return timegm(@t);
}

sub getfilesize {
	my ($self, $filename, $releaseid) = @_;

	return length($self->getfile($filename, $releaseid));
}

sub getfile {
	my ($self, $filename, $releaseid) = @_;

	my $fileh = $self->getfilehandle($filename, $releaseid);
	return undef unless $fileh;
	return join('', $fileh->getlines);
}

sub getannotations {
	my ($self, $filename, $releaseid) = @_;

	$self->parsecvs($filename);

	my $rev = $self->filerev($filename, $releaseid);
	return () unless defined($rev);

	my $hrev = $cvs{'header'}{'head'};
	my $lrev;
	my @anno;
	my $headfh = $self->getfilehandle($filename, $releaseid);
	my @head   = $headfh->getlines;

	while (1) {
		if ($rev eq $hrev) {
			@head = 0 .. $#head;
		}

		$lrev = $hrev;
		$hrev = $cvs{'branch'}{$hrev}{'next'} || last;

		my @diff = $self->getdiff($filename, $lrev, $hrev);
		my $off  = 0;

		while (@diff) {
			my $dir = shift(@diff);

			if ($dir =~ /^a(\d+)\s+(\d+)/) {
				splice(@diff, 0, $2);
				splice(@head, $1 - $off, 0, ('') x $2);
				$off -= $2;
			} elsif ($dir =~ /^d(\d+)\s+(\d+)/) {
				map { $anno[$_] = $lrev if $_ ne ''; } splice(@head, $1 - $off - 1, $2);

				$off += $2;
			} else {
				warn("Oops! Out of sync!");
			}
		}
	}

	if (@anno) {
		map { $anno[$_] = $lrev if $_ ne ''; } @head;
	}

	#	print(STDERR "** Anno: ".scalar(@anno).join("\n", '', @anno, ''));
	return @anno;
}

sub getauthor {
	my ($self, $filename, $revision) = @_;

	$self->parsecvs($filename);

	return $cvs{'branch'}{$revision}{'author'};
}

sub getfilehandle {
	my ($self, $filename, $releaseid) = @_;
	my ($fileh);

	$self->parsecvs($filename);

	my $rev = $self->filerev($filename, $releaseid);
	return undef unless defined($rev);

	return undef unless defined($self->toreal($filename, $releaseid));

	$rev =~ /([\d\.]*)/;
	$rev = $1;    # untaint
	my $clean_filename = $self->cleanstring($self->toreal($filename, $releaseid));
	$clean_filename =~ /(.*)/;
	$clean_filename = $1;    # technically untaint here (cleanstring did the real untainting)

	$ENV{'PATH'} = $self->{'path'};
	my $rtn;
	$rtn = open($fileh, "-|", "co -q -p$rev $clean_filename");

	die("Error executing \"co\"; rcs not installed?") unless $rtn;

	return $fileh;
}

sub getdiff {
	my ($self, $filename, $release1, $release2) = @_;
	my ($fileh);

	return () if $gnu_diff == 0;

	$self->parsecvs($filename);

	my $rev1 = $self->filerev($filename, $release1);
	return () unless defined($rev1);

	my $rev2 = $self->filerev($filename, $release2);
	return () unless defined($rev2);

	$rev1 =~ /([\d\.]*)/;
	$rev1 = $1;    # untaint
	$rev2 =~ /([\d\.]*)/;
	$rev2 = $1;    # untaint
	my $clean_filename = $self->cleanstring($self->toreal($filename, $release1));
	$clean_filename =~ /(.*)/;
	$clean_filename = $1;    # technically untaint here (cleanstring did the real untainting)

	$ENV{'PATH'} = $self->{'path'};
	open($fileh, "-|", "rcsdiff -q -a -n -r$rev1 -r$rev2 $clean_filename");

	die("Error executing \"rcsdiff\"; rcs not installed?") unless $fileh;
	return $fileh->getlines;
}

sub tmpfile {
	my ($self, $filename, $releaseid) = @_;
	my ($tmp,  $buf);

	$buf = $self->getfile($filename, $releaseid);
	return undef unless defined($buf);

	$tmp = $config->tmpdir . '/lxrtmp.' . time . '.' . $$ . '.' . &LXR::Common::tmpcounter;
	open(TMP, "> $tmp") || return undef;
	print(TMP $buf);
	close(TMP);

	return $tmp;
}

sub dirempty {
	my ($self, $pathname, $releaseid) = @_;
	my ($node, @dirs, @files);
	my $DIRH = new IO::Handle;
	my $real = $self->toreal($pathname, $releaseid);

	opendir($DIRH, $real) || return 1;
	while (defined($node = readdir($DIRH))) {
		next if $node =~ /^\.|~$|\.orig$/;
		next if $node eq 'CVS';

		if (-d $real . $node) {
			push(@dirs, $node . '/');
		} elsif ($node =~ /(.*),v$/) {
			push(@files, $1);
		}
	}
	closedir($DIRH);

	foreach $node (@files) {
		return 0 if $self->filerev($pathname . $node, $releaseid);
	}

	foreach $node (@dirs) {
		return 0 unless $self->dirempty($pathname . $node, $releaseid);
	}
	return 1;
}

sub getdir {
	my ($self, $pathname, $releaseid) = @_;
	my ($node, @dirs, @files);
	my $DIRH = new IO::Handle;
	my $real = $self->toreal($pathname, $releaseid);

	opendir($DIRH, $real) || return ();
  FILE: while (defined($node = readdir($DIRH))) {
		next if $node =~ /^\.|~$|\.orig$/;
		next if $node eq 'CVS';
		if (-d $real . $node) {
			foreach my $ignoredir ($config->ignoredirs) {
				next FILE if $node eq $ignoredir;
			}
			if ($node eq 'Attic') {
				push(@files, $self->getdir($pathname . $node . '/', $releaseid));
			} else {
				push(@dirs, $node . '/')
				  unless defined($releaseid)
				  && $self->dirempty($pathname . $node . '/', $releaseid);
			}
		} elsif ($node =~ /(.*),v$/) {
			if (!$$LXR::Common::HTTP{'param'}{'showattic'}) {

  # you can't just check for 'Attic' because for certain versions the file is alive even if in Attic
				$self->parsecvs($pathname . substr($node, 0, length($node) - 2))
				  ;    # substr is to remove the ',v'
				my $rev = $cvs{'header'}{'symbols'}{$releaseid};
				if ($cvs{'branch'}{$rev}{'state'} eq "dead") {
					next;
				}
			}
			push(@files, $1)
			  if !defined($releaseid)
			  || $self->getfiletime($pathname . $1, $releaseid);
		}
	}
	closedir($DIRH);

	return (sort(@dirs), sort(@files));
}

sub toreal {
	my ($self, $pathname, $releaseid) = @_;
	my $real = $self->{'rootpath'} . $pathname;

# nearly all (if not all) method calls eventually call toreal(), so this is a good place to block file access
	foreach my $ignoredir ($config->ignoredirs) {
		return undef if $real =~ m|/$ignoredir/|;
	}

	return $real if -d $real;

	if (!$$LXR::Common::HTTP{'param'}{'showattic'}) {

  # you can't just check for 'Attic' because for certain versions the file is alive even if in Attic
		$self->parsecvs($pathname);
		my $rev = $cvs{'header'}{'symbols'}{$releaseid};
		if ($cvs{'branch'}{$rev}{'state'} eq "dead") {
			return undef;
		}
	}

	return $real . ',v' if -f $real . ',v';

	$real =~ s|(/[^/]+/?)$|/Attic$1|;

	return $real        if -d $real;
	return $real . ',v' if -f $real . ',v';

	return undef;
}

sub cleanstring {
	my ($self, $in) = @_;

	my $out = '';

	for (split('', $in)) {
		s/[|&!`;\$%<>[:cntrl:]]//  ||    # `drop these in particular
		  /[\w\/,.-_+=]/           ||    # keep these intact
		  s/([ '"\x20-\x7E])/\\$1/ ||    # "'escape these out
		  s/.//;                         # drop everything else

		$out .= $_;
	}

	return $out;
}

sub isdir {
	my ($self, $pathname, $releaseid) = @_;

	return -d $self->toreal($pathname, $releaseid);
}

sub isfile {
	my ($self, $pathname, $releaseid) = @_;

	return -f $self->toreal($pathname, $releaseid);
}

sub getindex {
	my ($self, $pathname, $releaseid) = @_;

	my $index = $self->getfile($pathname, $releaseid);

	return $index =~ /\n(\S*)\s*\n\t-\s*([^\n]*)/gs;
}

sub allreleases {
	my ($self, $filename) = @_;

	$self->parsecvs($filename);

	# no header symbols for a directory, so we use the default and the current release
	if (defined %{ $cvs{'header'}{'symbols'} }) {
		return sort keys %{ $cvs{'header'}{'symbols'} };
	} else {
		my @releases;
		push @releases, $$LXR::Common::HTTP{'param'}{'v'} if $$LXR::Common::HTTP{'param'}{'v'};
		push @releases, $config->vardefault('v');
		return @releases;
	}
}

# sort by CVS version
#   split rev numbers into arrays
#   compare each array element, returning as soon as we find a difference
sub byrevision {
	my @one = split /\./, $a;
	my @two = split /\./, $b;
	for (my $i = 0; $i <= $#one; $i++) {
		my $ret = $one[$i] <=> $two[$i];
		return $ret if $ret;
	}

 # if still no difference after we ran through all elements of @one, compare the length of the array
	return $#one <=> $#two;
}

sub allrevisions {
	my ($self, $filename) = @_;

	$self->parsecvs($filename);

	return sort byrevision keys(%{ $cvs{'branch'} });
}

sub parsecvs {

	# Actually, these days it just parses the header.
	# RCS tools are much better at parsing RCS files.
	# -pok
	my ($self, $filename) = @_;

	return if $cache_filename eq $filename;
	$cache_filename = $filename;

	undef %cvs;

	my $file = '';
	open(CVS, $self->toreal($filename, undef));
	close CVS and return if -d CVS;    # we can't parse a directory
	while (<CVS>) {
		if (/^text\s*$/) {

			# stop reading when we hit the text.
			last;
		}
		$file .= $_;
	}
	close(CVS);

	my @cvs = $file =~ /((?:(?:[^\n@]+|@[^@]*@)\n?)+)/gs;

	$cvs{'header'} = {
		map {
			s/@@/@/gs;
			/^@/s && substr($_, 1, -1) || $_
		  } shift(@cvs) =~ /(\w+)\s*((?:[^;@]+|@[^@]*@)*);/gs
	};

	$cvs{'header'}{'symbols'} = { $cvs{'header'}{'symbols'} =~ /(\S+?):(\S+)/g };

	my ($orel, $nrel, $rev);
	while (($orel, $rev) = each %{ $cvs{'header'}{'symbols'} }) {
		$nrel = $config->cvsversion($orel);
		next unless defined($nrel);

		if ($nrel ne $orel) {
			delete($cvs{'header'}{'symbols'}{$orel});
			$cvs{'header'}{'symbols'}{$nrel} = $rev if $nrel;
		}
	}

	$cvs{'header'}{'symbols'}{'head'} = $cvs{'header'}{'head'};

	while (@cvs && $cvs[0] !~ /\s*desc/s) {
		my ($r, $v) = shift(@cvs) =~ /\s*(\S+)\s*(.*)/s;
		$cvs{'branch'}{$r} = {
			map {
				s/@@/@/gs;
				/^@/s && substr($_, 1, -1) || $_
			  } $v =~ /(\w+)\s*((?:[^;@]+|@[^@]*@)*);/gs
		};
	}
	delete $cvs{'branch'}{''};    # somehow an empty branch name gets in; delete it

	$cvs{'desc'} = shift(@cvs) =~ /\s*desc\s+((?:[^\n@]+|@[^@]*@)*)\n/s;
	$cvs{'desc'} =~ s/^@|@($|@)/$1/gs;

}

1;
