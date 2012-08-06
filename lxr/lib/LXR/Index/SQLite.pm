# -*- tab-width: 4 perl-indent-level: 4-*-
###############################
#
# $Id: SQLite.pm,v 1.1 2012/08/03 14:28:42 ajlittoz Exp $

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
###############################

package LXR::Index::SQLite;

$CVSID = '$Id: SQLite.pm,v 1.1 2012/08/03 14:28:42 ajlittoz Exp $ ';

use strict;
use DBI;
use LXR::Common;

our @ISA = ("LXR::Index");

our ($filenum, $symnum, $typenum);
our ($fileini, $symini, $typeini);

sub new {
	my ($self, $dbname, $prefix) = @_;

	$self = bless({}, $self);
	$self->{dbh} = DBI->connect($dbname)
	or fatal "Can't open connection to database: $DBI::errstr\n";

	$self->{'files_select'} =
		$self->{dbh}->prepare("select fileid from ${prefix}files where filename = ? and revision = ?");
	$self->{'files_insert'} =
		$self->{dbh}->prepare("insert into ${prefix}files (filename, revision, fileid) values (?, ?, ?)");

	$self->{'symbols_byname'} =
		$self->{dbh}->prepare("select symid from ${prefix}symbols where symname = ?");
	$self->{'symbols_byid'} =
		$self->{dbh}->prepare("select symname from ${prefix}symbols where symid = ?");
	$self->{'symnum_lastval'} = 
		$self->{dbh}->prepare("select sid from ${prefix}symnum");
	$self->{'symbols_insert'} =
		$self->{dbh}->prepare("insert into ${prefix}symbols (symname, symid) values ( ?, ?)");
	$self->{'symbols_remove'} =
		$self->{dbh}->prepare("delete from ${prefix}symbols where symname = ?");

	$self->{'definitions_select'} =
		$self->{dbh}->prepare("select f.filename, d.line, l.declaration, d.relid"
			. " from ${prefix}symbols s, ${prefix}definitions d, ${prefix}files f, ${prefix}releases r, ${prefix}langtypes l"
			. " where s.symid = d.symid"
			. " and d.fileid = r.fileid"
			. " and f.fileid = r.fileid"
			. " and d.langid = l.langid"
			. " and d.typeid = l.typeid"
			. " and s.symname = ? and r.releaseid = ?"
			. " order by f.filename, d.line, l.declaration");
	$self->{'definitions_insert'} =
		$self->{dbh}->prepare(
			"insert into ${prefix}definitions (symid, fileid, line, langid, typeid, relid) values (?, ?, ?, ?, ?, ?)"
		);

	$self->{'releases_select'} =
		$self->{dbh}->prepare("select * from ${prefix}releases where fileid = ? and  releaseid = ?");
	$self->{'releases_insert'} =
		$self->{dbh}->prepare("insert into ${prefix}releases (fileid, releaseid) values (?, ?)");

	$self->{'status_select'} =
		$self->{dbh}->prepare("select status from ${prefix}status where fileid = ?");
	$self->{'status_insert'} = $self->{dbh}->prepare
		("insert into ${prefix}status (fileid, relcount, status) values (?, 0, ?)");
	$self->{'status_update'} =
		$self->{dbh}->prepare("update ${prefix}status set status = ? where fileid = ?");

	$self->{'usages_insert'} =
		$self->{dbh}->prepare("insert into ${prefix}usages (fileid, line, symid) values (?, ?, ?)");
	$self->{'usages_select'} =
		$self->{dbh}->prepare("select f.filename, u.line"
			. " from ${prefix}symbols s, ${prefix}files f, ${prefix}releases r, ${prefix}usages u "
			. " where s.symid = u.symid"
			. " and f.fileid = r.fileid"
			. " and u.fileid = r.fileid"
			. " and s.symname = ?"
			. " and  r.releaseid = ?"
			. " order by f.filename, u.line");

	$self->{'langtypes_select'} =
		$self->{dbh}->prepare(
			"select typeid from ${prefix}langtypes where langid = ? and declaration = ?");
	$self->{'langtypes_insert'} =
		$self->{dbh}->prepare(
			"insert into ${prefix}langtypes (typeid, langid, declaration) values (?, ?, ?)");

	$self->{'delete_definitions'} =
		$self->{dbh}->prepare("delete from ${prefix}definitions"
			. " where fileid in"
			. "  (select fileid from ${prefix}releases where releaseid = ?)");
	$self->{'delete_usages'} =
		$self->{dbh}->prepare("delete from ${prefix}usages"
			. " where fileid in"
			. "  (select fileid from ${prefix}releases where releaseid = ?)");
	$self->{'delete_releases'} =
		$self->{dbh}->prepare("delete from ${prefix}releases where releaseid = ?");
	$self->{'delete_unused_files'} =
		$self->{dbh}->prepare("delete from ${prefix}status"
			. " where relcount = 0");

	$self->{'purge_langtypes'} =
		$self->{dbh}->prepare("delete from ${prefix}langtypes");
	$self->{'purge_files'} =
		$self->{dbh}->prepare("delete from ${prefix}files");
	$self->{'purge_definitions'} =
		$self->{dbh}->prepare("delete from ${prefix}definitions");
	$self->{'purge_releases'} =
		$self->{dbh}->prepare("delete from ${prefix}releases");
	$self->{'purge_status'} =
		$self->{dbh}->prepare("delete from ${prefix}status");
	$self->{'purge_symbols'} =
		$self->{dbh}->prepare("delete from ${prefix}symbols");
	$self->{'purge_usages'} =
		$self->{dbh}->prepare("delete from ${prefix}usages");

	$self->{'filenum_lastval'} = 
		$self->{dbh}->prepare("select fid from ${prefix}filenum");
	$self->{'filenum_lastval'}->execute();
	$filenum = $self->{'filenum_lastval'}->fetchrow_array();
	$self->{'filenum_lastval'} = undef;

	$self->{'symnum_lastval'} = 
		$self->{dbh}->prepare("select sid from ${prefix}symnum");
	$self->{'symnum_lastval'}->execute();
	$symnum = $self->{'symnum_lastval'}->fetchrow_array();
	$self->{'symnum_lastval'}  = undef;

	$self->{'typenum_lastval'} = 
		$self->{dbh}->prepare("select tid from ${prefix}typenum");
	$self->{'typenum_lastval'}->execute();
	$typenum = $self->{'typenum_lastval'}->fetchrow_array();
	$self->{'typenum_lastval'} = undef;

	$fileini = $filenum;
	$symini  = $symnum;
	$typeini = $typenum;

	$self->{'filenum_newval'} =
		$self->{dbh}->prepare("insert or replace"
			. " into ${prefix}filenum"
			. " (rcd, fid) values (0, $filenum)"
		);
	$self->{'symnum_newval'} =
		$self->{dbh}->prepare("insert or replace"
			. " into ${prefix}symnum"
			. " (rcd, sid) values (0, $symnum)"
		);
	$self->{'typenum_newval'} =
		$self->{dbh}->prepare("insert or replace"
			. " into ${prefix}typenum"
			. " (rcd, tid) values (0, $typenum)"
		);

	return $self;
}

sub DESTROY {
	my ($self) = @_;

	if ($filenum != $fileini) {
		$self->{'filenum_newval'}->execute();
	}
	if ($symnum != $symini) {
		$self->{'symnum_newval'}->execute();
	}
	if ($typenum != $typeini) {
		$self->{'typenum_newval'}->execute();
	}

	$self->{'files_insert'}       = undef;
	$self->{'files_select'}       = undef;
	$self->{'symbols_byname'}     = undef;
	$self->{'symbols_byid'}       = undef;
	$self->{'symbols_insert'}     = undef;
	$self->{'symbols_remove'}     = undef;
	$self->{'definitions_insert'} = undef;
	$self->{'definitions_select'} = undef;
	$self->{'releases_insert'}    = undef;
	$self->{'releases_select'}    = undef;
	$self->{'status_insert'}      = undef;
	$self->{'status_select'}      = undef;
	$self->{'status_update'}      = undef;
	$self->{'usages_insert'}      = undef;
	$self->{'usages_select'}      = undef;
	$self->{'langtypes_insert'}   = undef;
	$self->{'langtypes_select'}   = undef;
	$self->{'delete_definitions'} = undef;
	$self->{'delete_usages'}      = undef;
	$self->{'delete_releases'}    = undef;
	$self->{'delete_unused_files'}= undef;
	$self->{'purge_langtypes'}    = undef;
	$self->{'purge_files'}        = undef;
	$self->{'purge_definitions'}  = undef;
	$self->{'purge_releases'}     = undef;
	$self->{'purge_status'}       = undef;
	$self->{'purge_symbols'}      = undef;
	$self->{'purge_usages'}       = undef;
	$self->{'purge_all'}          = undef;
	$self->{'filenum_newval'}    = undef;
	$self->{'symnum_newval'}     = undef;
	$self->{'typenum_newval'}    = undef;

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

	unless (defined($fileid = $Index::files{"$filename\t$revision"})) {
		$self->{'files_select'}->execute($filename, $revision);
		$fileid = ++$filenum;
		$self->{'files_insert'}->execute($filename, $revision, $fileid);
		$self->{'status_insert'}->execute($fileid, 0);
		$Index::files{"$filename\t$revision"} = $fileid;
#        $self->{files_select}->finish();
	}
	return $fileid;
}

sub symid {
	my ($self, $symname) = @_;
	my ($symid);

	unless (defined($symid = $Index::symcache{$symname})) {
		$self->{'symbols_byname'}->execute($symname);
		$symid = ++$symnum;
		$self->{'symbols_insert'}->execute($symname, $symid);
		$Index::symcache{$symname} = $symid;
	}

	return $symid;
}

sub decid {
	my ($self, $lang, $string) = @_;

	my $rows = $self->{'langtypes_select'}->execute($lang, $string);
	$self->{'langtypes_select'}->finish();

	unless ($rows > 0) {
		my $declid = ++$typenum;
		$self->{'langtypes_insert'}->execute($declid, $lang, $string);
	}

	$self->{'langtypes_select'}->execute($lang, $string);
	my $id = $self->{'langtypes_select'}->fetchrow_array();
	$self->{'langtypes_select'}->finish();

	return $id;
}

sub purgeall {
	my ($self) = @_;

	$self->{dbh}->begin_work;
	$self->{'purge_definitions'}->execute();
	$self->{'purge_usages'}->execute();
	$self->{'purge_langtypes'}->execute();
	$self->{'purge_symbols'}->execute();
	$self->{'purge_releases'}->execute();
	$self->{'purge_status'}->execute();
	$self->{'purge_files'}->execute();
	$self->{dbh}->commit;
}

1;
