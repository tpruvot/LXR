# -*- tab-width: 4 perl-indent-level: 4-*-
###############################
#
# $Id: SQLite.pm,v 1.3 2012/11/14 11:27:31 ajlittoz Exp $
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

package LXR::Index::SQLite;

$CVSID = '$Id: SQLite.pm,v 1.3 2012/11/14 11:27:31 ajlittoz Exp $ ';

use strict;
use DBI;
use LXR::Common;

our @ISA = ("LXR::Index");

our ($filenum, $symnum, $typenum);
our ($fileini, $symini, $typeini);

# NOTE;
#	Some Perl statements below are commented out as '# opt'.
#	This is meant to decrease the number of calls to DBI methods,
#	in this case finish() since we know the previous fetch_array()
#	did retrieve all selected rows.
#	The warning message is removed through undef'ing the DBI
#	prepares in final_cleanup before disconnecting.
#	The time advantage is negligible, if any, on the test cases. It
#	is not known if it grows to an appreciable difference on huge
#	trees, such as the Linux kernel.
#
#	If strict rule observance is preferred, uncomment the '# opt'.
#	You can leave the undef'ing in final_cleanup, they are executed
#	only once and do not contribute to the running time behaviour.

sub new {
	my ($self, $dbname, $prefix) = @_;

	$self = bless({}, $self);
	$self->{dbh} = DBI->connect($dbname)
	or fatal "Can't open connection to database: $DBI::errstr\n";
#	SQLite is forced into explicit commit mode as the medium-sized
#	test cases have shown a 40-times (!) performance improvement
#	over auto commit.
	$self->{dbh}{'AutoCommit'} = 0;

	$self->{'files_insert'} =
		$self->{dbh}->prepare("insert into ${prefix}files (filename, revision, fileid) values (?, ?, ?)");

	$self->{'symbols_insert'} =
		$self->{dbh}->prepare
			( "insert into ${prefix}symbols"
			. " (symname, symid, symcount) values"
			. " (?, ?, 0)"
			);

	$self->{'langtypes_insert'} =
		$self->{dbh}->prepare
			( "insert into ${prefix}langtypes"
			. " (typeid, langid, declaration)"
			. " values (?, ?, ?)"
			);

	$self->{'purge_all'} = undef;	# Prevent parsing the common one
	$self->{'purge_definitions'} =
		$self->{dbh}->prepare("delete from ${prefix}definitions");
	$self->{'purge_usages'} =
		$self->{dbh}->prepare("delete from ${prefix}usages");
	$self->{'purge_langtypes'} =
		$self->{dbh}->prepare("delete from ${prefix}langtypes");
	$self->{'purge_symbols'} =
		$self->{dbh}->prepare("delete from ${prefix}symbols");
	$self->{'purge_releases'} =
		$self->{dbh}->prepare("delete from ${prefix}releases");
	$self->{'purge_status'} =
		$self->{dbh}->prepare("delete from ${prefix}status");
	$self->{'purge_files'} =
		$self->{dbh}->prepare("delete from ${prefix}files");

#	Since SQLite has no auto-incrementing counter,
#	we simulate them in specific one-record tables.
#	These counters provide unique record ids for
#	files, symbols and language types.

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
		$self->{dbh}->prepare
			( "update ${prefix}filenum"
			. " set fid = ?"
			. " where rcd = 0"
			);

	$self->{'symnum_newval'} =
		$self->{dbh}->prepare
			( "update ${prefix}symnum"
			. " set sid = ?"
			. " where rcd = 0"
		);
	$self->{'typenum_newval'} =
		$self->{dbh}->prepare
			( "update ${prefix}typenum"
			. " set tid = ?"
			. " where rcd = 0"
			);

	return $self;
}

#
# LXR::Index API Implementation
#

sub fileid {
	my ($self, $filename, $revision) = @_;
	my ($fileid);
	$fileid = $self->fileidifexists($filename, $revision);
	unless ($fileid) {
		$fileid = ++$filenum;
		$self->{'files_insert'}->execute($filename, $revision, $fileid);
		$self->{'status_insert'}->execute($fileid, 0);
# 			$self->commit;
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
			$symid = ++$symnum;
			$symcount = 0;
			$self->{'symbols_insert'}->execute($symname, $symid);
		}
		$LXR::Index::symcache{$symname} = $symid;
		$LXR::Index::cntcache{$symname} = -$symcount;
	}

	return $symid;
}

sub decid {
	my ($self, $lang, $string) = @_;
	my $declid;

	$self->{'langtypes_select'}->execute($lang, $string);
	($declid) = $self->{'langtypes_select'}->fetchrow_array();
# opt	$self->{'langtypes_select'}->finish();
	unless (defined($declid)) {
		$declid = ++$typenum;
		$self->{'langtypes_insert'}->execute($declid, $lang, $string);
	}

	return $declid;
}

sub purgeall {
	my ($self) = @_;

# Not really necessary, but nicer for debugging
	$self->{'filenum_newval'}->execute(0);
	$self->{'symnum_newval'}->execute(0);
	$self->{'typenum_newval'}->execute(0);
	$filenum = 0;
	$symnum = 0;
	$typenum = 0;
	$fileini = $filenum;
	$symini  = $symnum;
	$typeini = $typenum;

	$self->{'purge_definitions'}->execute();
	$self->{'purge_usages'}->execute();
	$self->{'purge_langtypes'}->execute();
	$self->{'purge_symbols'}->execute();
	$self->{'purge_releases'}->execute();
	$self->{'purge_status'}->execute();
	$self->{'purge_files'}->execute();
	$self->{dbh}->commit;
}

sub final_cleanup {
	my ($self) = @_;

	if ($filenum != $fileini) {
		$self->{'filenum_newval'}->execute($filenum);
	}
	if ($symnum != $symini) {
		$self->{'symnum_newval'}->execute($symnum);
	}
	if ($typenum != $typeini) {
		$self->{'typenum_newval'}->execute($typenum);
	}
	$self->{dbh}->commit;
	$self->{'files_select'} = undef;
	$self->{'releases_select'} = undef;
	$self->{'status_select'} = undef;
	$self->{'langtypes_select'} = undef;
	$self->{'symbols_byname'} = undef;
	$self->{dbh}->disconnect() or die "Disconnect failed: $DBI::errstr";
}

1;
