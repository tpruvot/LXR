# -*- tab-width: 4 perl-indent-level: 4-*-
###############################
#
# $Id: Postgres.pm,v 1.37 2012/11/14 11:27:31 ajlittoz Exp $
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
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#
###############################

package LXR::Index::Postgres;

$CVSID = '$Id: Postgres.pm,v 1.37 2012/11/14 11:27:31 ajlittoz Exp $ ';

use strict;
use DBI;
use LXR::Common;

our @ISA = ("LXR::Index");

sub new {
	my ($self, $dbname, $prefix) = @_;

	$self = bless({}, $self);
	$self->{dbh} = DBI->connect	( $dbname
								, $config->{'dbuser'}
								, $config->{'dbpass'}
#	From the measurement on the medium sized test cases used to 
#	debug LXR, PostgreSQL performance is as follows:
#	- auto commit mode:		10-11 time units
#	- auto commit mode with begin_work (see below):
#							1 time unit
#	- explicit commit mode:	1 time unit
#	To change commit policy, change the following constant and
#	eventually comment out begin_work() call.
								, {'AutoCommit' => 0}
								)
	or fatal "Can't open connection to database: $DBI::errstr\n";

#	Without the following instruction (theoretically meaningless
#	in auto commit mode), indexing time is multiplied by 10
#	on the test case!
#	$self->{dbh}->begin_work() or die "begin_work failed: $DBI::errstr";

	$self->{'filenum_nextval'} = 
		$self->{dbh}->prepare("select nextval('${prefix}filenum')");
	$self->{'files_insert'} =
		$self->{dbh}->prepare
			( "insert into ${prefix}files"
			. " (filename, revision, fileid)"
			. " values (?, ?, ?)"
			);

	$self->{'symnum_nextval'} = 
		$self->{dbh}->prepare("select nextval('${prefix}symnum')");
	$self->{'symbols_insert'} =
		$self->{dbh}->prepare
			( "insert into ${prefix}symbols"
			. " (symname, symid, symcount)"
			. " values (?, ?, 0)"
			);

	$self->{'typeid_nextval'} = 
		$self->{dbh}->prepare("select nextval('${prefix}typenum')");

	$self->{'langtypes_insert'} =
		$self->{dbh}->prepare
			( "insert into ${prefix}langtypes"
			. " (typeid, langid, declaration)"
			. " values (?, ?, ?)"
			);

	$self->{'delete_definitions'} =
		$self->{dbh}->prepare
			( "delete from ${prefix}definitions as d"
			. " using ${prefix}status t, ${prefix}releases r"
			. " where r.releaseid = ?"
			. "  and  t.fileid = r.fileid"
			. "  and  t.relcount = 1"
			. "  and  d.fileid = r.fileid"
			);
	$self->{'delete_usages'} =
		$self->{dbh}->prepare
			( "delete from ${prefix}usages as u"
			. " using ${prefix}status t, ${prefix}releases r"
			. " where r.releaseid = ?"
			. " and t.fileid = r.fileid"
			. " and t.relcount = 1"
			. " and u.fileid = r.fileid"
			);

	$self->{'reset_filenum'} = $self->{dbh}->prepare
		("select setval('${prefix}filenum', 1, false)");
	$self->{'reset_symnum'} = $self->{dbh}->prepare
		("select setval('${prefix}symnum',  1, false)");
	$self->{'reset_typenum'} = $self->{dbh}->prepare
		("select setval('${prefix}typenum', 1, false)");

	return $self;
}

#
# LXR::Index API Implementation
#

sub fileid {
	my ($self, $filename, $revision) = @_;
	my $fileid;

	$fileid = $self->fileidifexists($filename, $revision);
	unless ($fileid) {
		$self->{'filenum_nextval'}->execute();
		($fileid) = $self->{'filenum_nextval'}->fetchrow_array();
		$self->{'files_insert'}->execute($filename, $revision, $fileid);
		$self->{'status_insert'}->execute($fileid, 0);
		$LXR::Index::files{"$filename\t$revision"} = $fileid;
	}
	return $fileid;
}

sub symid {
	my ($self, $symname) = @_;
	my $symid;
	my $symcount;

	unless (defined($symid = $LXR::Index::symcache{$symname})) {
		$self->{'symbols_byname'}->execute($symname);
		($symid, $symcount) = $self->{'symbols_byname'}->fetchrow_array();
		unless ($symid) {
			$self->{'symnum_nextval'}->execute();
			($symid) = $self->{'symnum_nextval'}->fetchrow_array();
			$self->{'symbols_insert'}->execute($symname, $symid);
			$symcount = 0;
		}
		$LXR::Index::symcache{$symname} = $symid;
		$LXR::Index::cntcache{$symname} = -$symcount;
	}

	return $symid;
}

sub decid {
	my ($self, $lang, $string) = @_;
	my $id;

	$self->{'langtypes_select'}->execute($lang, $string);
	($id) = $self->{'langtypes_select'}->fetchrow_array();
	unless (defined($id)) {
		$self->{'typeid_nextval'}->execute();
		($id) = $self->{'typeid_nextval'}->fetchrow_array();
		$self->{'langtypes_insert'}->execute($id, $lang, $string);
	}
	
	return $id;
}

sub purgeall {
	my ($self) = @_;

# Not really necessary, but nicer for debugging
	$self->{'reset_filenum'}->execute;
	$self->{'reset_symnum'}->execute;
	$self->{'reset_typenum'}->execute;

	$self->{'purge_all'}->execute;
}

#	PostgreSQL is in auto commit mode; disable calls to
#	commit to suppress warning messages.
sub commit{}

sub final_cleanup {
	my ($self) = @_;

	$self->{dbh}{'AutoCommit'} = 0;
	$self->{dbh}->commit();		# Force a real commit
	$self->{'filenum_nextval'} = undef;
	$self->{'symnum_nextval'} = undef;
	$self->{'typeid_nextval'} = undef;
	$self->{'reset_filenum'} = undef;
	$self->{'reset_symnum'} = undef;
	$self->{'reset_typenum'} = undef;
	$self->{'files_select'} = undef;
# 	$self->{'allfiles_select'} = undef;
	$self->{'releases_select'} = undef;
	$self->{'status_select'} = undef;
	$self->{'releases_select'} = undef;
	$self->{'langtypes_select'} = undef;
# 	$self->{'definitions_select'} = undef;
# 	$self->{'usages_select'} = undef;
	$self->{'symbols_byname'} = undef;
# 	$self->{'symbols_byid'} = undef;
# 	$self->{'related_symbols_select'} = undef;
	$self->{dbh}->disconnect() or die "Disconnect failed: $DBI::errstr";
}

1;
