# -*- tab-width: 4 perl-indent-level: 4-*- ###############################
#
# $Id: Postgres.pm,v 1.35 2012/08/03 14:27:45 ajlittoz Exp $

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

package LXR::Index::Postgres;

$CVSID = '$Id: Postgres.pm,v 1.35 2012/08/03 14:27:45 ajlittoz Exp $ ';

use strict;
use DBI;
use LXR::Common;

our @ISA = ("LXR::Index");

sub new {
	my ($self, $dbname, $prefix) = @_;

	$self = bless({}, $self);
	$self->{dbh} = DBI->connect($dbname, $config->{'dbuser'}, $config->{'dbpass'})
	or fatal "Can't open connection to database: $DBI::errstr\n";

	$self->{dbh}->begin_work() or die "begin_work failed: $DBI::errstr";

	$self->{'files_select'} =
		$self->{dbh}->prepare("select fileid from ${prefix}files where filename = ? and revision = ?");
	$self->{'filenum_nextval'} = 
		$self->{dbh}->prepare("select nextval('${prefix}filenum')");
	$self->{'files_insert'} =
		$self->{dbh}->prepare("insert into ${prefix}files (filename, revision, fileid) values (?, ?, ?)");

	$self->{'symbols_byname'} =
		$self->{dbh}->prepare("select symid from ${prefix}symbols where symname = ?");
	$self->{'symbols_byid'} =
		$self->{dbh}->prepare("select symname from ${prefix}symbols where symid = ?");
	$self->{'symnum_nextval'} = 
		$self->{dbh}->prepare("select nextval('${prefix}symnum')");
	$self->{'symbols_insert'} =
		$self->{dbh}->prepare("insert into ${prefix}symbols (symname, symid) values (?, ?)");
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
		$self->{dbh}->prepare("insert into ${prefix}definitions (symid, fileid, line, langid, typeid, relid) "
			. "values (?, ?, ?, ?, ?, ?)");

	$self->{'releases_select'} =
		$self->{dbh}->prepare("select * from ${prefix}releases where fileid = ? and releaseid = ?");
	$self->{'releases_insert'} =
		$self->{dbh}->prepare("insert into ${prefix}releases (fileid, releaseid) values (?, ?)");

	$self->{'status_select'} =
		$self->{dbh}->prepare("select status from ${prefix}status where fileid = ?");
	$self->{'status_insert'} = $self->{dbh}->prepare
		("insert into ${prefix}status (fileid, status) values (?, ?)");
	$self->{'status_update'} =
		$self->{dbh}->prepare("update ${prefix}status set status = ? where fileid = ?");

	$self->{'usages_insert'} =
		$self->{dbh}->prepare("insert into ${prefix}usages (fileid, line, symid) values (?, ?, ?)");
	$self->{'usages_select'} =
		$self->{dbh}->prepare("select f.filename, u.line"
			. " from ${prefix}symbols s, ${prefix}files f, ${prefix}releases r, ${prefix}usages u"
			. " where s.symid = u.symid"
			. " and f.fileid = r.fileid"
			. " and u.fileid = r.fileid"
			. " and s.symname = ? and  r.releaseid = ?"
			. " order by f.filename, u.line");

	$self->{'typeid_nextval'} = 
		$self->{dbh}->prepare("select nextval('${prefix}typenum')");

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
		( "truncate table ${prefix}definitions, ${prefix}usages, ${prefix}langtypes"
		. ", ${prefix}symbols, ${prefix}releases, ${prefix}status"
		. ", ${prefix}files"
		.	" cascade"
		);

	return $self;
}

sub DESTROY {
	my ($self) = @_;
    
	$self->{'files_insert'}       = undef;
	$self->{'files_select'}       = undef;
	$self->{'filenum_nextval'}    = undef;
	$self->{'symbols_byname'}     = undef;
	$self->{'symbols_byid'}       = undef;
	$self->{'symnum_nextval'}     = undef;
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
	$self->{'langtypes_select'}   = undef;
	$self->{'langtypes_insert'}   = undef;
	$self->{'typeid_nextval'}     = undef;
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
		$self->{dbh}->commit() or die "Commit failed: $DBI::errstr";
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
		($fileid) = $self->{'files_select'}->fetchrow_array();
		unless ($fileid) {
			$self->{'filenum_nextval'}->execute();
			($fileid) = $self->{'filenum_nextval'}->fetchrow_array();
			$self->{'files_insert'}->execute($filename, $revision, $fileid);
			$self->{'status_insert'}->execute($fileid, 0);
		}
		$Index::files{"$filename\t$revision"} = $fileid;
#        $self->{files_select}->finish();
	}
	return $fileid;
}

sub setfilerelease {
    my ($self, $fileid, $releaseid) = @_;

    $self->{'releases_select'}->execute($fileid + 0, $releaseid);
    my $firstrow = $self->{'releases_select'}->fetchrow_array();

#    $self->{releases_select}->finish();

    unless ($firstrow) {
        $self->{'releases_insert'}->execute($fileid + 0, $releaseid);
    }
}

sub symdeclarations {
    my ($self, $symname, $releaseid) = @_;
    my ($rows, @ret, @row);

    $rows = $self->{'definitions_select'}->execute("$symname", "$releaseid");

    while (@row = $self->{'definitions_select' }->fetchrow_array) {
        $row[3] &&= $self->symname($row[3]); # convert the symid

        # Also need to remove trailing whitespace erroneously added by the db 
        # interface that isn't actually stored in the underlying db
        $row[2] =~ s/^(.+?)\s+$/$1/;

        push(@ret, [@row]);
    }
    $self->{'definitions_select'}->finish();

    return @ret;
}

sub issymbol {
    my ($self, $symname, $releaseid) = @_; # TODO make full use of $releaseid

    unless (exists($Index::symcache{$symname})) {
        $self->{'symbols_byname'}->execute($symname);
        ($Index::symcache{$symname}) = $self->{'symbols_byname'}->fetchrow_array();
    }

    return $Index::symcache{$symname};
}

sub symid {
    my ($self, $symname) = @_;
    my ($symid);

    unless (defined($symid = $Index::symcache{$symname})) {
        $self->{'symbols_byname'}->execute($symname);
        ($symid) = $self->{'symbols_byname'}->fetchrow_array();
        unless ($symid) {
            $self->{'symnum_nextval'}->execute();
            ($symid) = $self->{'symnum_nextval'}->fetchrow_array();
            $self->{'symbols_insert'}->execute($symname, $symid);
        }
        $Index::symcache{$symname} = $symid;
    }

    return $symid;
}

sub decid {
    my ($self, $lang, $string) = @_;

    my $rows = $self->{'langtypes_select'}->execute($lang, $string);
    $self->{'langtypes_select'}->finish();

    unless ($rows > 0) {
        $self->{'typeid_nextval'}->execute();
        my ($declid) = $self->{'typeid_nextval'}->fetchrow_array();
        $self->{'langtypes_insert'}->execute($declid, $lang, $string);
    }

    $self->{'langtypes_select'}->execute($lang, $string);
    my $id = $self->{'langtypes_select'}->fetchrow_array();
    $self->{'langtypes_select'}->finish();
    
    return $id;
}
# 
# sub purge {
#     my ($self, $releaseid) = @_;
# 
#     # we don't delete symbols, because they might be used by other versions
#     # so we can end up with unused symbols, but that doesn't cause any problems
#     $self->{delete_indexes}->execute($releaseid);
#     $self->{delete_usage}->execute($releaseid);
#     $self->{delete_status}->execute($releaseid);
#     $self->{delete_releases}->execute($releaseid);
#     $self->{delete_files}->execute($releaseid);
# 
#     $self->commit() or die "Commit failed: $DBI::errstr";
# }

sub commit {
    my ($self) = @_;
    $self->{dbh}->commit;
	$self->{dbh}->begin_work;
}
# 
# sub purgeall {
#     my ($self) = @_;
# 
#     # special sub for a clean '--allversions' indexation with VCSes
#     $self->{purge_declarations}->execute();
#     $self->{purge_files}->execute();
#     $self->{purge_indexes}->execute();
#     $self->{purge_releases}->execute();
#     $self->{purge_status}->execute();
#     $self->{purge_symbols}->execute();
#     $self->{purge_usage}->execute();
# }

1;
