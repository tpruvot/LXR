# -*- tab-width: 4 -*- ###############################################
#
# $Id: Index.pm,v 1.17 2009/05/14 21:13:07 mbox Exp $

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

package LXR::Index;

$CVSID = '$Id: Index.pm,v 1.17 2009/05/14 21:13:07 mbox Exp $ ';

use LXR::Common;
use strict;

sub new {
    my ($self, $dbname, @args) = @_;
    my $index;

    if ($dbname =~ /^DBI:/i) {
        require LXR::Index::DBI;
        $index = new LXR::Index::DBI($dbname, @args);
    } else {
        die "Can't find database, $dbname";
    }
    return $index;
}

#
# Stub implementations of this interface
#

sub fileid {
    my ($self, $filename, $revision) = @_;     # CAUTION: $revision is not $releaseid!  
    my $fileid;
    warn  __PACKAGE__."::fileid not implemented. Parameters @_";
    return $fileid;
}

# Indicate that the file referred to by $fileid is part of $releaseid
sub setfilerelease {
    my ($self, $fileid, $releaseid) = @_;
    warn  __PACKAGE__."::setfilerelease not implemented. Parameters @_";
    return;
}

# If the file referred to by $fileid has already been indexed return true.
# Otherwise return false.
sub fileindexed {
    my ($self, $fileid) = @_;
    my $filefoundboolean;
    warn  __PACKAGE__."::fileindexed not implemented. Parameters @_";
    return $filefoundboolean;
}

sub setfileindexed {
    my ($self, $fileid) = @_;
    warn  __PACKAGE__."::setfileindexed not implemented. Parameters @_";
    return;
}

# If the file referred to by $fileid has already been referenced
#  return true.  Otherwise return false.  NOTE: a file must *always*
#  be indexed before being referenced - calling setfilereferenced
#  implicitly sets fileindexed as well

sub filereferenced {
    my ($self, $fileid) = @_;
    my $referencefoundboolean;
    warn  __PACKAGE__."::filereferenced not implemented. Parameters @_";
    return $referencefoundboolean;
}

sub setfilereferenced {
    my ($self, $fileid) = @_;
    warn  __PACKAGE__."::setfilereferenced not implemented. Parameters @_";
    return;
}

sub symdeclarations {
    my ($self, $symname, $releaseid) = @_;
    my @indexes;
    warn  __PACKAGE__."::symdeclarations not implemented. Parameters @_";
    return @indexes;
}

sub setsymdeclaration {
    my ($self, $symname, $fileid, $line, $langid, $type, $relsym) = @_;
    warn  __PACKAGE__."::setsymdeclaration not implemented. Parameters @_";
    return;
}

sub symreferences {
    my ($self, $symname, $releaseid) = @_;
    my @references;
    warn  __PACKAGE__."::symreferences not implemented. Parameters @_";
    return @references;
}

sub setsymreference {
    my ($self, $symname, $fileid, $line) = @_;
    warn  __PACKAGE__."::setsymreference not implemented. Parameters @_";
    return;
}

sub issymbol {
    my ($self, $symname, $releaseid) = @_;
    my $symbolfoundboolean;
    warn  __PACKAGE__."::issymbol not implemented. Parameters @_";
    return $symbolfoundboolean;
}

sub symid {
    my ($self, $symname) = @_;
    my $symid;
    warn  __PACKAGE__."::symid not implemented. Parameters @_";
    return $symid;
}

sub symname {
    my ($self, $symid) = @_;
    my $symname;
    warn  __PACKAGE__."::symname not implemented. Parameters @_";
    return $symname;
}

sub decid {
    my ($self, $lang, $string) = @_;
    my $decid;
    warn  __PACKAGE__."::decid not implemented. Parameters @_";
    return $decid;
}

# Commit the last set of operations and start a new transaction
# If transactions are not supported, it's OK for this to be a no-op

sub commit {
    my ($self) = @_;
    warn  __PACKAGE__."::commit not implemented. Parameters @_";
}

# This function should be called before parsing each new file,
# if this is not done then too much memory will be used and
# things will become very slow.
sub emptycache {
    my ($self) = @_;
    warn  __PACKAGE__."::emptycache not implemented. Parameters @_";
    return;
}

sub purge {
    my ($self, $releaseid) = @_;
    warn  __PACKAGE__."::purge not implemented. Parameters @_";
    return;
}

1;
