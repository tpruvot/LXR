# -*- tab-width: 4 -*- ###############################################
#
# $Id: Plain.pm,v 1.26 2009/05/10 11:54:29 adrianissott Exp $

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

package LXR::Files::Subversion;

$CVSID = '$Id: Plain.pm,v 1.26 2009/05/10 11:54:29 adrianissott Exp $ ';

use strict;
use FileHandle;
use LXR::Common;
use LWP::Simple;
use LWP::UserAgent;
use Date::Parse;

use vars qw( @ISA $debug );

$debug = 0;

@ISA = ("LXR::Files");

sub new {
	my ($self, $rootpath) = @_;

	$self = bless({}, $self);
        $rootpath=~ s{/$}{};
	$self->{'rootpath'} = $rootpath;

	return $self;
}

sub revpath {
   my ($self,$filename,$releaseid) = @_;
   my ($res);

   print "enter: revpath $filename, $releaseid \n" if ($debug);

   if ($releaseid =~ m{head|trunk}) {
       $releaseid = 'trunk';
   } else {
       $releaseid = 'tags/$releaseid';
   }
   $res =  "$self->{'rootpath'}/$releaseid$filename";
   print "returning  '$res'\n" if ($debug);
   return $res;
}


sub filerev {
	my ($self, $filename, $releaseid) = @_;

	return $releaseid;
}

sub getfiletime {
	my ($self, $filename, $releaseid) = @_;
        my ($res);

        print "enter: getfiletime($filename, $releaseid)\n" if ($debug);

        $res = head($self->revpath($filename,$releaseid));
	return (str2time($res->{'_headers'}->{'last-modified'}));
}

sub getfilesize {
	my ($self, $filename, $releaseid) = @_;
        my ($res);

        print "enter: getfilesize($filename, $releaseid)\n" if ($debug);

        $res = head($self->revpath($filename,$releaseid));
	return (int($res->{'_headers'}->{'content-length'}));
}

sub getfile {
	my ($self, $filename, $releaseid) = @_;
	my ($res);
	local ($/) = undef;

        print "enter: getfile($filename, $releaseid)\n" if ($debug);

        $res = get($self->revpath($filename,$releaseid));
	return $res;
}

sub getfilehandle {
	my ($self, $filename, $releaseid) = @_;
	my ($fileh, $id, $res);

        print "enter: getfilehandle($filename, $releaseid)\n" if ($debug);

        my $ua = LWP::UserAgent->new;
        my $req = HTTP::Request->new(GET => $self->revpath($filename, $releaseid));
        $res = $ua->request($req,"/tmp/gfh$$");
        $fileh = FileHandle->new("/tmp/gfh$$");
        unlink("/tmp/gfh$$");

	return $fileh;
}

sub getannotations {
	my ($self, $filename, $releaseid) = @_;
        my (@res, $uri);

        print "enter: getannotations($filename, $releaseid)\n" if ($debug);

        $uri = $self->revpath($filename,$releaseid);
        $uri =~ m{([\s\w:/]+)};
        $uri = $1;
        $ENV{PATH} =~ m{.*};
        $ENV{PATH} = $1;
        open(ANNO,"svn annotate $uri |");
        while( <ANNO> ) { 
           print "got line: $_" if ($debug);
           if( m{\A\s*(\d+)\s.*} ) {
              push(@res, $1);
           }
        }
        close(ANNO);
        print "getannotations returning @res\n" if ($debug);
	return @res;
}

sub getauthor {
	my ($self, $filename, $releaseid) = @_;
        my ($res);

        print "enter: getauthor($filename, $releaseid)\n" if ($debug);

        $ENV{PATH} =~ m{.*};
        $ENV{PATH} = $1;
        open(LOG,"svn log " . $self->revpath($filename,$releaseid) . "|");
        $res = "unknown";
        while(<LOG>){
            if ( m{^r[0-9]+ \| (\w+) \|}  ) {
                $res = $1;
                last;
            }
        }
        close(LOG);
	return $res;
}

sub getdir {
	my ($self, $pathname, $releaseid) = @_;
	my ($dir, $node, @dirs, @files, $res, $path);

        print "enter: getdir($pathname, $releaseid)\n" if ($debug);

	if($pathname !~ m!/$!) {
		$pathname = $pathname . '/';
	}

        $path = $self->revpath($pathname,$releaseid);

        print "back in getdir, path is $path\n" if ($debug);
        $res =  get($path);

        print "listing is:\n------\n$res\n-----------\n" if ($debug);

        # trim off up to .. listing
        $res =~ s{(.*)<a href="\.\./">\.\.</a>}{};
FILE:
        while ($res =~ s{.*<a href="([^"]*)">[^<]*</a>}{}) {
           print "found node $node\n" if ($debug);
           $node = $1;
           if ($node =~ m{http:}) {
               last;
           }
           if ($node =~ m{/$}) {
	      foreach my $ignoredir ($config->ignoredirs) {
		next FILE if $node eq $ignoredir;
	      }
              push(@dirs, $node);
           } else {
              push(@files, $node);
           }
        }
		
        print "returning ", join(',',@dirs), "; ", join(',',@files), "\n" if ($debug);
	return sort(@dirs), sort(@files);
}


sub isdir {
	my ($self, $pathname, $releaseid) = @_;
        my ($res);

        print "enter: isdir($pathname, $releaseid)\n" if ($debug);

        $res = head($self->revpath($pathname,$releaseid));
	return ($res->{'_headers'}->{'content-type'} eq 'text/html');
}

sub isfile {
	my ($self, $pathname, $releaseid) = @_;
        my ($res);

        print "enter: isfile($pathname, $releaseid)\n" if ($debug);

        $res = head($self->revpath($pathname,$releaseid));;
	return ($res->{'_headers'}->{'content-type'} eq 'text/plain');
}

sub getindex {
	my ($self, $pathname, $releaseid) = @_;
	my ($index);

        print "enter: getindex($pathname, $releaseid)\n" if ($debug);

	my $index = $self->getfile($pathname, $releaseid);

	return $index =~ /\n(\S*)\s*\n\t-\s*([^\n]*)/gs;
}

sub tmpfile {
	my ($self, $filename, $releaseid) = @_;
	my ($tmp, $tries);
	local ($/) = undef;

        print "enter: tmpfile($filename, $releaseid)\n" if ($debug);
	$tmp = $config->tmpdir . '/lxrtmp.' . time . '.' . $$ . '.' . &LXR::Common::tmpcounter;
	open(TMP, "> $tmp") || return undef;
	print(TMP $self->getfile($filename, $releaseid));
	close(FILE);
	close(TMP);

	return $tmp;
}

1;
