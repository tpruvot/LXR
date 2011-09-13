# -*- tab-width: 4 perl-indent-level: 4-*- ###############################
#
# $Id: Oracle.pm,v 1.22 2009/05/14 21:13:07 mbox Exp $

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

package LXR::Index::Oracle;

$CVSID = '$Id: Oracle.pm,v 1.22 2009/05/14 21:13:07 mbox Exp $ ';

use strict;
use DBI;
use LXR::Common;

our @ISA = ("LXR::Index");

#
# Global variables
#
my (%files, %symcache);

sub new {
    my ($self, $dbname) = @_;

    $self = bless({}, $self);

    $self->{dbh} =
      DBI->connect($dbname, $config->{dbuser}, $config->{dbpass},
        { RaiseError => 1, AutoCommit => 1 })
      or fatal "Can't open connection to database: $DBI::errstr\n";

    my $prefix;
    if (defined($config->{'dbprefix'})) {
        $prefix = $config->{'dbprefix'};
    } else {
        $prefix = "lxr_";
    }

    %files        = ();
    %symcache     = ();

    $self->{files_select} =
      $self->{dbh}->prepare("select fileid from ${prefix}files where filename = ? and revision = ?");
    $self->{files_insert} =
      $self->{dbh}->prepare("insert into ${prefix}files values (?, ?, ${prefix}filenum.nextval)");

    $self->{symbols_byname} =
      $self->{dbh}->prepare("select symid from ${prefix}symbols where symname = ?");
    $self->{symbols_byid} =
      $self->{dbh}->prepare("select symname from ${prefix}symbols where symid = ?");
    $self->{symbols_insert} =
      $self->{dbh}->prepare("insert into ${prefix}symbols values ( ?, ${prefix}symnum.nextval)");
    $self->{symbols_remove} =
      $self->{dbh}->prepare("delete from ${prefix}symbols where symname = ?");

    $self->{indexes_select} =
      $self->{dbh}->prepare("select f.filename, i.line, d.declaration, i.relsym "
          . "from ${prefix}symbols s, ${prefix}indexes i, ${prefix}files f, ${prefix}releases r, ${prefix}declarations d "
          . "where s.symid = i.symid and i.fileid = f.fileid "
          . "and f.fileid = r.fileid "
          . "and i.langid = d.langid and i.type = d.declid "
          . "and s.symname = ? and r.releaseid = ? "
          . "order by f.filename, i.line, d.declaration");
    $self->{indexes_insert} =
      $self->{dbh}->prepare(
        "insert into ${prefix}indexes (symid, fileid, line, langid, type, relsym) values (?, ?, ?, ?, ?, ?)"
      );

    $self->{releases_select} =
      $self->{dbh}->prepare("select * from ${prefix}releases where fileid = ? and  releaseid = ?");
    $self->{releases_insert} =
      $self->{dbh}->prepare("insert into ${prefix}releases (fileid, releaseid) values (?, ?)");

    $self->{status_select} =
      $self->{dbh}->prepare("select status from ${prefix}status where fileid = ?");

    $self->{status_insert} = $self->{dbh}->prepare
      ("insert into ${prefix}status (fileid, status) values (?, ?)");

    $self->{status_update} =
      $self->{dbh}->prepare("update ${prefix}status set status = ? where fileid = ? and status <= ?");

    $self->{usage_insert} =
      $self->{dbh}->prepare("insert into ${prefix}usage (fileid, line, symid) values (?, ?, ?)");
    $self->{usage_select} =
      $self->{dbh}->prepare("select f.filename, u.line "
          . "from ${prefix}symbols s, ${prefix}files f, ${prefix}releases r, ${prefix}usage u "
          . "where s.symid = u.symid "
          . "and f.fileid = u.fileid "
          . "and u.fileid = r.fileid "
          . "and s.symname = ? and  r.releaseid = ? "
          . "order by f.filename, u.line");
    $self->{decl_select} =
      $self->{dbh}->prepare(
        "select declid from ${prefix}declarations where langid = ? and declaration = ?");
    $self->{decl_insert} =
      $self->{dbh}->prepare(
        "insert into ${prefix}declarations (declid, langid, declaration) values (${prefix}declnum.nextval, ?, ?)");

    $self->{delete_indexes} =
      $self->{dbh}->prepare("delete from ${prefix}indexes "
          . "where fileid in "
          . "  (select fileid from ${prefix}releases where releaseid = ?)");
    $self->{delete_usage} =
      $self->{dbh}->prepare("delete from ${prefix}usage "
          . "where fileid in "
          . "  (select fileid from ${prefix}releases where releaseid = ?)");
    $self->{delete_status} =
      $self->{dbh}->prepare("delete from ${prefix}status "
          . "where fileid in "
          . "  (select fileid from ${prefix}releases where releaseid = ?)");
    $self->{delete_releases} =
      $self->{dbh}->prepare("delete from ${prefix}releases where releaseid = ?");
    $self->{delete_files} =
      $self->{dbh}->prepare("delete from ${prefix}files "
          . "where fileid in "
          . "  (select fileid from ${prefix}releases where releaseid = ?)");

    return $self;
}

sub DESTROY {
    my ($self) = @_;
    $self->{files_select}    = undef;
    $self->{files_insert}    = undef;
    $self->{symbols_byname}  = undef;
    $self->{symbols_byid}    = undef;
    $self->{symbols_insert}  = undef;
    $self->{indexes_insert}  = undef;
    $self->{releases_insert} = undef;
    $self->{status_insert}   = undef;
    $self->{status_update}   = undef;
    $self->{usage_insert}    = undef;
    $self->{usage_select}    = undef;
    $self->{decl_select}     = undef;
    $self->{decl_insert}     = undef;
    $self->{delete_indexes}  = undef;
    $self->{delete_usage}    = undef;
    $self->{delete_status}   = undef;
    $self->{delete_releases} = undef;
    $self->{delete_files}    = undef;

    if ($self->{dbh}) {
        $self->{dbh}->disconnect() or die "Disconnect failed: $DBI::errstr";
        $self->{dbh} = undef;
    }
}

#
# LXR::Index API Implementation
#

sub fileid {
    my ($self, $filename, $revision) = @_;
    my ($fileid);

    unless (defined($fileid = $files{"$filename\t$revision"})) {
        $self->{files_select}->execute($filename, $revision);
        ($fileid) = $self->{files_select}->fetchrow_array();
        unless ($fileid) {
            $self->{files_insert}->execute($filename, $revision);
            $self->{files_select}->execute($filename, $revision);
            ($fileid) = $self->{files_select}->fetchrow_array();
        }
        $files{"$filename\t$revision"} = $fileid;
        $self->{files_select}->finish();
    }
    return $fileid;
}

sub setfilerelease {
    my ($self, $fileid, $releaseid) = @_;

    my $rows = $self->{releases_select}->execute($fileid + 0, $releaseid);
    $self->{releases_select}->finish();

    unless ($rows > 0) {
        $self->{releases_insert}->execute($fileid, $releaseid);
    }
}

sub fileindexed {
    my ($self, $fileid) = @_;
    my ($status);

    $self->{status_select}->execute($fileid);
    $status = $self->{status_select}->fetchrow_array();
    $self->{status_select}->finish();

    if (!defined($status)) {
        $status = 0;
    }
    return $status;
}

sub setfileindexed {
    my ($self, $fileid) = @_;
    my ($status);
    
    $self->{status_select}->execute($fileid);
    $status = $self->{status_select}->fetchrow_array();
    $self->{status_select}->finish();

    if (!defined($status)) {
        $self->{status_insert}->execute($fileid + 0, 1);
    } else {
        $self->{status_update}->execute(1, $fileid, 0);
    }
}

sub filereferenced {
    my ($self, $fileid) = @_;
    my ($status);

    $self->{status_select}->execute($fileid);
    $status = $self->{status_select}->fetchrow_array();
    $self->{status_select}->finish();

    return defined($status) && $status == 2;
}

sub setfilereferenced {
    my ($self, $fileid) = @_;
    my ($status);
    
    $self->{status_select}->execute($fileid);
    $status = $self->{status_select}->fetchrow_array();
    $self->{status_select}->finish();

    if (!defined($status)) {
        $self->{status_insert}->execute($fileid + 0, 2);
    } else {
        $self->{status_update}->execute(2, $fileid, 1);
    }
}

sub symdeclarations {
    my ($self, $symname, $releaseid) = @_;
    my ($rows, @ret, @row);

    $rows = $self->{indexes_select}->execute("$symname", "$releaseid");
    while (@row = $self->{indexes_select}->fetchrow_array) {
        $row[3] &&= $self->symname($row[3]); # convert the symid
        push(@ret, [@row]);
    }
    $self->{indexes_select}->finish();

    return @ret;
}

sub setsymdeclaration {
    my ($self, $symname, $fileid, $line, $langid, $type, $relsym) = @_;

    $self->{indexes_insert}->execute($self->symid($symname),
    $fileid, $line, $langid, $type, $relsym ? $self->symid($relsym) : undef);
}

sub symreferences {
    my ($self, $symname, $releaseid) = @_;
    my ($rows, @ret, @row);

    $rows = $self->{usage_select}->execute("$symname", "$releaseid");

    while (@row = $self->{usage_select}->fetchrow_array) {
        push(@ret, [@row]);
    }

    $self->{usage_select}->finish();

    return @ret;
}

sub setsymreference {
    my ($self, $symname, $fileid, $line) = @_;

    $self->{usage_insert}->execute($fileid, $line, $self->symid($symname));
}

sub issymbol {
    my ($self, $symname, $releaseid) = @_; # TODO make full use of $releaseid
    my ($symid);

    $symid = $symcache{$releaseid}{$symname};
    unless (defined($symid)) {
        $self->{symbols_byname}->execute($symname);
        ($symid) = $self->{symbols_byname}->fetchrow_array();
        $self->{symbols_byname}->finish();
        $symcache{$releaseid}{$symname} = $symid;
    }

    return $symid;
}

sub symid {
    my ($self, $symname) = @_;
    my ($symid);

    $symid = $symcache{$symname};
    unless (defined($symid)) {
        $self->{symbols_byname}->execute($symname);
        ($symid) = $self->{symbols_byname}->fetchrow_array();
        $self->{symbols_byname}->finish();
        unless ($symid) {
            $self->{symbols_insert}->execute($symname);

            # Get the id of the new symbol
            $self->{symbols_byname}->execute($symname);
            ($symid) = $self->{symbols_byname}->fetchrow_array();
            $self->{symbols_byname}->finish();
        }
        $symcache{$symname} = $symid;
    }

    return $symid;
}

sub symname {
    my ($self, $symid) = @_;
    my ($symname);

    $self->{symbols_byid}->execute($symid + 0);
    ($symname) = $self->{symbols_byid}->fetchrow_array();
    $self->{symbols_byid}->finish();

    return $symname;
}

sub decid {
    my ($self, $lang, $string) = @_;

    my $rows = $self->{decl_select}->execute($lang, $string);
    $self->{decl_select}->finish();

    unless ($rows > 0) {
        $self->{decl_insert}->execute($lang, $string);
    }

    $self->{decl_select}->execute($lang, $string);
    my $id = $self->{decl_select}->fetchrow_array();
    $self->{decl_select}->finish();

    return $id;
}

sub commit {
    my ($self) = @_;
    $self->{dbh}->commit;
	$self->{dbh}->begin_work;
}


sub emptycache {
    %symcache = ();
}

sub purge {
    my ($self, $releaseid) = @_;

    # we don't delete symbols, because they might be used by other versions
    # so we can end up with unused symbols, but that doesn't cause any problems
    $self->{delete_indexes}->execute($releaseid);
    $self->{delete_usage}->execute($releaseid);
    $self->{delete_status}->execute($releaseid);
    $self->{delete_releases}->execute($releaseid);
    $self->{delete_files}->execute($releaseid);
}

1;
