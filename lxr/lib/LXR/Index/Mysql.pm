# -*- tab-width: 4 perl-indent-level: 4-*-
###############################
#
# $Id: Mysql.pm,v 1.34 2012/08/03 14:27:45 ajlittoz Exp $

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

package LXR::Index::Mysql;

$CVSID = '$Id: Mysql.pm,v 1.34 2012/08/03 14:27:45 ajlittoz Exp $ ';

use strict;
use DBI;
use LXR::Common;

our @ISA = ("LXR::Index");

sub new {
	my ($self, $dbname, $prefix) = @_;

	$self = bless({}, $self);
	if (defined($config->{dbpass})) {
		$self->{dbh} = DBI->connect($dbname, $config->{'dbuser'}, $config->{'dbpass'})
	} else {
		$self->{dbh} = DBI->connect($dbname, $config->{'dbuser'})
		or fatal "Can't open connection to database: $DBI::errstr\n";
	}

	$self->{'files_select'} =
		$self->{dbh}->prepare("select fileid from ${prefix}files where filename = ? and revision = ?");
	$self->{'files_insert'} =
		$self->{dbh}->prepare("insert into ${prefix}files (filename, revision, fileid) values (?, ?, NULL)");

	$self->{'symbols_byname'} =
		$self->{dbh}->prepare("select symid from ${prefix}symbols where symname = ?");
	$self->{'symbols_byid'} =
		$self->{dbh}->prepare("select symname from ${prefix}symbols where symid = ?");
	$self->{'symbols_insert'} =
		$self->{dbh}->prepare("insert into ${prefix}symbols (symname, symid) values ( ?, NULL)");
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
			"insert into ${prefix}langtypes (typeid, langid, declaration) values (NULL, ?, ?)");

	$self->{'delete_definitions'} =
		$self->{dbh}->prepare("delete from d"
			. " using ${prefix}definitions d, ${prefix}releases r"
			. " where d.fileid = r.fileid"
			. " and r.releaseid = ?");
	$self->{'delete_usages'} =
		$self->{dbh}->prepare("delete from u"
			. " using ${prefix}usages u, ${prefix}releases r"
			. " where u.fileid = r.fileid"
			. " and r.releaseid = ?");
	$self->{'delete_releases'} =
		$self->{dbh}->prepare("delete from ${prefix}releases where releaseid = ?");
	$self->{'delete_unused_files'} =
		$self->{dbh}->prepare("delete from s"
			. " using ${prefix}status s"
			. " where relcount = 0");

	$self->{'purge_langtypes'} =
		$self->{dbh}->prepare("truncate table ${prefix}langtypes");
	$self->{'purge_files'} =
		$self->{dbh}->prepare("truncate table ${prefix}files");
	$self->{'purge_definitions'} =
		$self->{dbh}->prepare("truncate table ${prefix}definitions");
	$self->{'purge_releases'} =
		$self->{dbh}->prepare("truncate table ${prefix}releases");
	$self->{'purge_status'} =
		$self->{dbh}->prepare("truncate table ${prefix}status");
	$self->{'purge_symbols'} =
		$self->{dbh}->prepare("truncate table ${prefix}symbols");
	$self->{'purge_usages'} =
		$self->{dbh}->prepare("truncate table ${prefix}usages");

	$self->{'purge_all'} = $self->{dbh}->prepare
		( "call ${prefix}purgeall()"
		);

	return $self;
}

sub DESTROY {
	my ($self) = @_;
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

	if ($self->{dbh}) {
		$self->{dbh}->disconnect() or die "Disconnect failed: $DBI::errstr";
		$self->{dbh} = undef;
	}
}


# MySQL is put into "auto-commit mode". This sub only aims at
# suppressing a disturbing warning message in genxref.

sub commit {}

1;
