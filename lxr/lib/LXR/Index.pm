# -*- tab-width: 4 -*-
###############################################
#
# $Id: Index.pm,v 1.28 2013/11/20 14:58:18 ajlittoz Exp $
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
###############################################

=head1 Index module

This module defines the abstract access methods to the database.
If needed, the methods are overridden in the specific modules.

=cut

package LXR::Index;

$CVSID = '$Id: Index.pm,v 1.28 2013/11/20 14:58:18 ajlittoz Exp $ ';

use strict;

#
# Global variables
#
our (%files, %symcache, %cntcache);
our $database_id = 0;	# DB counter incremented by genxref or httpinit
	# This variable is incremented every time a new DB is opened
	# so that objects 'or procedures) which cache their initialisation
	# are able to detect DB has change and can synchronise to a fresh
	# new DB.

my ($filenum, $symnum, $typenum);	# Counters for unique record id
my ($fileini, $symini, $typeini);	#	user management


=head2 C<new ($dbname)>

C<new> is Index object constructor.
It dispatches to the specific constructor based on its argument.

=over

=item 1 C<$dbname>

a I<string> containing the condiguration parameter C<'dbname'>
describing the engine and the characteristics of the DB

=back

B<Note:>

=over

=item

I<There used to be a second C<@args> argument which passed file
open-attributes (such as C<O_RDWR> or C<O_CREAT>) when the DB
was made of a set of files.
This is no longer used with DB engines.>

=back

The specific constructor is responsible for creating hash elements
in C<$self> containing "cooked" queries (meaning they have been
processed by C<prepare> DBD method.

They are mentioned by the I<Requires> paragraphs in the following
method descriptions.

=cut

# NOTE:
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
	my ($self, $config) = @_;
	my $index;
    
	%files    = ();
	%symcache = ();    
	%cntcache = ();

	if (!defined($config->{'dbprefix'})) {
		$config->{'dbprefix'} = 'lxr_';
	}

	if ($config->{'dbname'} =~ m/^DBI:(\w+):/i) {
		my $dbname = uc($1);
		if ('MYSQL' eq $dbname) {
			require  LXR::Index::Mysql;
			$index = LXR::Index::Mysql->new($config);
		} elsif ('PG' eq $dbname) {
			require  LXR::Index::Postgres;
			$index = LXR::Index::Postgres->new($config);
		} elsif ('SQLITE' eq $dbname) {
			require  LXR::Index::SQLite;
			$index = LXR::Index::SQLite->new($config);
		} elsif ('ORACLE' eq $dbname) {
			require  LXR::Index::Oracle;
			$index = LXR::Index::Oracle->new($config);
		} else {
			die 'Can\'t find database ' . $config->{'dbname'};
		}
	} else {
		die 'Can\'t find database ' . $config->{'dbname'};
	}
	$index->{'config'} = $config;

	# Common syntax transactions
	# Care is taken not to replace specific syntax transactions which
	# are usually related to auto-increment numbering where syntax
	# differs from one DB engine to another.
	my $prefix = $config->{'dbprefix'};

	if (!exists($index->{'files_insert'})) {
		$index->{'files_insert'} =
			$index->{dbh}->prepare
				( "insert into ${prefix}files"
				. ' (filename, revision, fileid)'
				. ' values (?, ?, ?)'
				);
	}
	if (!exists($index->{'files_select'})) {
		$index->{'files_select'} =
			$index->{dbh}->prepare
				( "select fileid from ${prefix}files"
				. ' where filename = ? and revision = ?'
				);
	}
	if (!exists($index->{'allfiles_select'})) {
		$index->{'allfiles_select'} =
			$index->{dbh}->prepare
				( 'select f.fileid, f.filename, f.revision, t.relcount'
				. " from ${prefix}files f, ${prefix}status t"
				.		", ${prefix}releases r"
				. ' where r.releaseid = ?'
				. '  and  f.fileid = r.fileid'
				. '  and  t.fileid = r.fileid'
				. ' order by f.filename, f.revision'
				);
	}

	if (!exists($index->{'symbols_insert'})) {
		$index->{'symbols_insert'} =
			$index->{dbh}->prepare
				( "insert into ${prefix}symbols"
				. ' (symname, symid, symcount)'
				. ' values (?, ?, 0)'
				);
	}
	if (!exists($index->{'symbols_byname'})) {
		$index->{'symbols_byname'} =
			$index->{dbh}->prepare
				( "select symid, symcount from ${prefix}symbols"
				. ' where symname = ?'
				);
	}
	if (!exists($index->{'symbols_byid'})) {
		$index->{'symbols_byid'} =
			$index->{dbh}->prepare
				( "select symname from ${prefix}symbols"
				. ' where symid = ?'
				);
	}
	if (!exists($index->{'symbols_setref'})) {
		$index->{'symbols_setref'} =
			$index->{dbh}->prepare
				( "update ${prefix}symbols"
				. ' set symcount = ?'
				. ' where symid = ?'
				);
	}
	if (!exists($index->{'related_symbols_select'})) {
		$index->{'related_symbols_select'} =
			$index->{dbh}->prepare
				( 'select s.symid, s.symcount, s.symname'
				. " from ${prefix}symbols s, ${prefix}definitions d"
				. ' where d.fileid = ?'
				. '  and  s.symid = d.relid'
				);
	}
	if (!exists($index->{'delete_symbols'})) {
		$index->{'delete_symbols'} =
			$index->{dbh}->prepare
				( "delete from ${prefix}symbols"
				. ' where symcount = 0'
				);
	}

	if (!exists($index->{'definitions_insert'})) {
		$index->{'definitions_insert'} =
			$index->{dbh}->prepare
				( "insert into ${prefix}definitions"
				. ' (symid, fileid, line, langid, typeid, relid)'
				. ' values (?, ?, ?, ?, ?, ?)'
				);
	}
	if (!exists($index->{'definitions_select'})) {
		$index->{'definitions_select'} =
			$index->{dbh}->prepare
				( 'select f.filename, d.line, l.declaration, d.relid'
				. " from ${prefix}symbols s, ${prefix}definitions d"
				.		", ${prefix}files f, ${prefix}releases r"
				.		", ${prefix}langtypes l"
				. ' where s.symname = ?'
				. '  and  r.releaseid = ?'
				. '  and  d.fileid = r.fileid'
				. '  and  d.symid  = s.symid'
				. '  and  d.langid = l.langid'
				. '  and  d.typeid = l.typeid'
				. '  and  f.fileid = r.fileid'
				. ' order by f.filename, d.line, l.declaration'
				);
	}
	if (!exists($index->{'delete_file_definitions'})) {
		$index->{'delete_file_definitions'} =
			$index->{dbh}->prepare
				( "delete from ${prefix}definitions"
				. ' where fileid  = ?'
				);
	}
	# 'delete_definitions' mandatory but syntax varies
	if (!exists($index->{'delete_definitions'})) {
		$index->{'delete_definitions'} =
			$index->{dbh}->prepare
				( "delete from ${prefix}definitions"
				. ' where fileid in'
				.	' (select r.fileid'
				.	"  from ${prefix}releases r, ${prefix}status t"
				.	'  where r.releaseid = ?'
				.	'   and  t.fileid = r.fileid'
				.	'   and  t.relcount = 1'
				.	' )'
				);
	}

	if (!exists($index->{'releases_insert'})) {
		$index->{'releases_insert'} =
			$index->{dbh}->prepare
				( "insert into ${prefix}releases"
				. ' (fileid, releaseid)'
				. ' values (?, ?)'
				);
	}
	if (!exists($index->{'releases_select'})) {
		$index->{'releases_select'} =
			$index->{dbh}->prepare
				( "select fileid from ${prefix}releases"
				. ' where fileid = ?'
				. ' and  releaseid = ?'
				);
	}
	if (!exists($index->{'delete_one_release'})) {
		$index->{'delete_one_release'} =
			$index->{dbh}->prepare
				( "delete from ${prefix}releases"
				. ' where fileid = ?'
				. '  and  releaseid = ?'
				);
	}
	if (!exists($index->{'delete_releases'})) {
		$index->{'delete_releases'} =
			$index->{dbh}->prepare
				( "delete from ${prefix}releases"
				. ' where releaseid = ?'
				);
	}

	if (!exists($index->{'status_insert'})) {
		$index->{'status_insert'} =
			$index->{dbh}->prepare
				( "insert into ${prefix}status"
				. ' (fileid, relcount, indextime, status)'
				. ' values (?, 0, 0, ?)'
				);
	}
	if (!exists($index->{'status_select'})) {
		$index->{'status_select'} =
			$index->{dbh}->prepare
				( "select status from ${prefix}status"
				. ' where fileid = ?'
				);
	}
	if (!exists($index->{'status_update'})) {
		$index->{'status_update'} =
			$index->{dbh}->prepare
				( "update ${prefix}status"
				. ' set status = ?'
				. ' where fileid = ?'
				);
	}
	if (!exists($index->{'status_timestamp'})) {
		$index->{'status_timestamp'} =
			$index->{dbh}->prepare
				( "select indextime from ${prefix}status"
				. ' where fileid = ?'
				);
	}
	if (!exists($index->{'status_update_timestamp'})) {
		$index->{'status_update_timestamp'} =
			$index->{dbh}->prepare
				( "update ${prefix}status"
				. ' set indextime = ?'
				. ' where fileid = ?'
				);
	}
	if (!exists($index->{'delete_unused_status'})) {
		$index->{'delete_unused_status'} =
			$index->{dbh}->prepare
				( "delete from ${prefix}status"
				. ' where relcount = 0'
				);
	}

	if (!exists($index->{'usages_insert'})) {
		$index->{'usages_insert'} =
			$index->{dbh}->prepare
				( "insert into ${prefix}usages"
				. ' (fileid, line, symid)'
				. ' values (?, ?, ?)'
				);
	}
	if (!exists($index->{'usages_select'})) {
		$index->{'usages_select'} =
			$index->{dbh}->prepare
				( 'select f.filename, u.line'
				. " from ${prefix}symbols s, ${prefix}files f"
				.	", ${prefix}releases r, ${prefix}usages u"
				. ' where s.symname = ?'
				. '  and  r.releaseid = ?'
				. '  and  u.symid  = s.symid'
				. '  and  f.fileid = r.fileid'
				. '  and  u.fileid = r.fileid'
				. ' order by f.filename, u.line'
				);
	}
	if (!exists($index->{'delete_file_usages'})) {
		$index->{'delete_file_usages'} =
			$index->{dbh}->prepare
				( "delete from ${prefix}usages"
				. ' where fileid  = ?'
				);
	}
	# 'delete_definitions' mandatory but syntax varies
	if (!exists($index->{'delete_usages'})) {
		$index->{'delete_usages'} =
			$index->{dbh}->prepare
				( "delete from ${prefix}usages"
				. ' where fileid in'
				.	' (select r.fileid'
				.	"  from ${prefix}releases r, ${prefix}status t"
				.	'  where r.releaseid = ?'
				.	'   and  t.fileid = r.fileid'
				.	'   and  t.relcount = 1'
				.	' )'
				);
	}

	if (!exists($index->{'langtypes_insert'})) {
		$index->{'langtypes_insert'} =
			$index->{dbh}->prepare
				( "insert into ${prefix}langtypes"
				. ' (typeid, langid, declaration)'
				. ' values (?, ?, ?)'
				);
	}
	if (!exists($index->{'langtypes_select'})) {
		$index->{'langtypes_select'} =
			$index->{dbh}->prepare
				( "select typeid from ${prefix}langtypes"
				. ' where langid = ?'
				. ' and declaration = ?'
				);
	}
	if (!exists($index->{'langtypes_count'})) {
		$index->{'langtypes_count'} =
			$index->{dbh}->prepare
				( "select count(*) from ${prefix}langtypes"
				);
	}

	if (!exists($index->{'purge_all'})) {
		$index->{'purge_all'} =
			$index->{dbh}->prepare
				( "truncate table ${prefix}definitions"
				. ", ${prefix}usages, ${prefix}langtypes"
				. ", ${prefix}symbols, ${prefix}releases"
				. ", ${prefix}status, ${prefix}files"
				. ' cascade'
				);
	}
	return $index;
}

=head2 C<uniquecountersinit ($prefix)>

C<uniquecountersinit> initialises the unique counters for
file, symbol and type ids.

I<This is a C<new> extension method for derived object usage.>

=over

=item 1 C<$prefix>

a I<string> containing the database table prefix

=back

Several database engines have better performance using cached counters
for fields with C<unique> attributes unstead of the built-in features.
It comes from the fact that the used (incremented) value is not written
back immediately to disk (fewer commits).

This trick is valid because e write to the DB only at I<genxref> time
and DB loading is B<single thread>.

B<CAUTION!>

=over

B<Don't forget to write the final values to the DB before disconnecting.
See C<uniquecounterssave>.>

=back

=cut

sub uniquecountersinit {
	my ($self, $prefix) = @_;

	$self->{'filenum_lastval'} = 
		$self->{dbh}->prepare("select fid from ${prefix}filenum");
	$self->{'filenum_lastval'}->execute();
	$fileini = $filenum = $self->{'filenum_lastval'}->fetchrow_array();
	$self->{'filenum_lastval'} = undef;

	$self->{'symnum_lastval'} = 
		$self->{dbh}->prepare("select sid from ${prefix}symnum");
	$self->{'symnum_lastval'}->execute();
	$symini = $symnum = $self->{'symnum_lastval'}->fetchrow_array();
	$self->{'symnum_lastval'}  = undef;

	$self->{'typenum_lastval'} = 
		$self->{dbh}->prepare("select tid from ${prefix}typenum");
	$self->{'typenum_lastval'}->execute();
	$typeini = $typenum = $self->{'typenum_lastval'}->fetchrow_array();
	$self->{'typenum_lastval'} = undef;
}


#
# Generic implementation of this interface
#

=head2 C<fileid ($filename, $revision)>

=head2 C<fileidifexists ($filename, $revision)>

C<fileid> returns a unique id for a file with a given revision,
creating it if it does not exist.

C<fileidifexists> is similar, but returns C<undef> if the given
revision is unknown, which can happen if the revision was created
after the latest I<genxref> indexation.

=over

=item 1 C<$filename>

a I<string> containing the path relative to C<'sourceroot'>

=item 1 C<$revision>

the revision for the file

B<CAUTION:> this is not a release id!
It is computed by method C<filerev> in the I<Files> classes.

=back

The result is used as an index between the different DB tables
to refer to the file.

B<Requires:>

=over

=item * C<files_select>

=item * C<files_insert>

=item * C<status_insert>
B<I<(>C<fileid> I<only)>>

=back

=cut

sub fileidifexists {
# Reminder:	my ($self, $filename, $revision) = @_;
	my $self = shift @_;
	my $fileid;

# 	unless (defined($fileid = $files{"$filename\t$revision"})) {
		$self->{'files_select'}->execute(@_);
		($fileid) = $self->{'files_select'}->fetchrow_array();
# opt		$self->{'files_select'}->finish();
# 		$files{"$filename\t$revision"} = $fileid;
# 	}
	return $fileid
}

sub fileid {
# Reminder:	my ($self, $filename, $revision) = @_;
	my $self = shift @_;
	my $fileid;

	$fileid = $self->fileidifexists(@_);
	unless ($fileid) {
		$fileid = ++$filenum;
		$self->{'files_insert'}->execute(@_, $fileid);
		$self->{'status_insert'}->execute($fileid, 0);
# 			$self->commit;
# 		$files{"$filename\t$revision"} = $fileid;
	}
	return $fileid;
}

=head2 C<getallfilesinit ($releaseid)>

C<getallfilesinit> prepares things for C<nextfile>.

=over

=item 1 C<$releaseid>

the release (or version) for which all recorded files should be returned

=back

The subroutine executes the C<allfiles_select> transaction.
Results are retrieved one by one through C<nextfile>.

B<Requires:>

=over

=item * C<allfiles_select>

=back

=cut

sub getallfilesinit {
	my ($self, $releaseid) = @_;

	$self->{'allfiles_select'}->execute($releaseid);
}

=head2 C<nextfile ()>

C<nextfile> is an iterator running over all files making up a version
of the source tree, as known from the database.

A file description is returned for each call until it returns C<undef>,
at which time it must no longer be called.

B<Requires:>

=over

=item * Previous initialisation by C<getallfilesinit>

=back

=cut

sub nextfile {
	my $self = shift @_;

	return $self->{'allfiles_select'}->fetchrow_array();
# opt		$self->{'files_select'}->finish();
}

=head2 C<setfilerelease ($fileid, $releaseid)>

C<setfilerelease> marks the file referred to by
C<$fileid> as part of C<$releaseid>.

=over

=item 1 C<$fileid>

an I<integer> representing a file in the DB

=item 1 C<$releaseid>

the release (or version) containing the file

=back

B<Requires:>

=over

=item * C<releases_select>

=item * C<releases_insert>

=back

The final result is as many records in the I<releases> tables as
I<versions> of this file. All these records point to the same
item in the I<files> table.

The I<releaseid> is any tag under which the file in this state
is known by the VCS.
The I<revision>, stored in the I<files> table, is a canonical
identification of the file state.
The file state will be parsed and cross-referenced only once,
thus reducing C<genxref> processing time, but the result may
still be referenced by any tag.

=cut

sub setfilerelease {
# 	my ($self, $fileid, $releaseid) = @_;
	my $self = shift @_;

	$self->{'releases_select'}->execute(@_);
    my ($fid) = $self->{'releases_select'}->fetchrow_array();
# opt	$self->{'releases_select'}->finish();
	unless ($fid) {
		$self->{'releases_insert'}->execute(@_);
	}
}

=head2 C<removerelease ($fid, $releaseid)>

C<removerelease> deletes one release from the set associated to a
base revision.

=over

=item 1 C<$fid>

the unique id for a base revision file

=item 1 C<$releaseid>

the release (or version) containing the file

=back

B<Requires:>

=over

=item * C<delete_one_release>

=back

=cut

sub removerelease {
# 	my ($self, $fid, $releaseid) = @_;
	my $self = shift @_;

	$self->{'delete_one_release'}->execute(@_);
}

=head2 C<fileindexed ($fileid)>

C<fileindexed> returns true is the file referred to by
C<$fileid> has already been indexed;
otherwise, it returns false.

=over

=item 1 C<$fileid>

an I<integer> representing a file in the DB

=back

B<Requires:>

=over

=item C<status_select>

=back

=cut

sub fileindexed {
	my ($self, $fileid) = @_;
	my $status;

	$self->{'status_select'}->execute($fileid);
	($status) = $self->{'status_select'}->fetchrow_array();
# opt	$self->{'status_select'}->finish();

	return defined($status) && $status & 1;
}

=head2 C<setfileindexed ($fileid)>

C<setfileindexed> marks the file referred to by
C<$fileid> as being indexed.

Since indexing (i.e. symbol definition collecting) is usually
done outside LXR, indexing time is not updated.

=over

=item 1 C<$fileid>

an I<integer> representing a file in the DB

=back

B<Requires:>

=over

=item * C<status_select>

=item * C<status_insert>

=item * C<status_update>

=back

=cut

sub setfileindexed {
	my ($self, $fileid) = @_;
	my $status;

	$self->{'status_select'}->execute($fileid);
	($status) = $self->{'status_select'}->fetchrow_array();
# opt	$self->{'status_select'}->finish();
	if (!defined($status)) {
		print STDERR "$fileid status not defined!\n";
		$self->{'status_insert'}->execute($fileid + 0, 1);
	} elsif (!($status & 1)) {
		$self->{'status_update'}->execute($status|1, $fileid);
	}
}

=head2 C<filereferenced ($fileid)>

C<filereferenced> returns true is the file referred to by
C<$fileid> has already been parsed for references;
otherwise, it returns false.

=over

=item 1 C<$fileid>

an I<integer> representing a file in the DB

=back

B<Requires:>

=over

=item * C<status_select>

=back

=cut

sub filereferenced {
	my ($self, $fileid) = @_;
	my $status;

	$self->{'status_select'}->execute($fileid);
	($status) = $self->{'status_select'}->fetchrow_array();
# opt	$self->{'status_select'}->finish();

	return defined($status) && $status & 2;
}

=head2 C<setfilereferenced ($fileid)>

C<setfilereferenced> marks the file referred to by
C<$fileid> as having been parsed for references.

Indexing time is updated for user information.

=over

=item 1 C<$fileid>

an I<integer> representing a file in the DB

=back

B<Note:>

=over

=item

I<A file must> always I<be indexed before being parsed for
references.>

=back

B<Requires:>

=over

=item * C<status_select>

=item * C<status_insert>

=item * C<status_update>

=item * C<status_update_timestamp>

=back

=cut

sub setfilereferenced {
	my ($self, $fileid) = @_;
	my $status;
    
	$self->{'status_select'}->execute($fileid);
	($status) = $self->{'status_select'}->fetchrow_array();
# opt	$self->{'status_select'}->finish();
	if (!defined($status)) {
		print STDERR "$fileid status not defined!\n";
		$self->{'status_insert'}->execute($fileid + 0, 2);
	} elsif (!($status & 2)) {
		$self->{'status_update'}->execute($status|2, $fileid);
	}
	$self->{'status_update_timestamp'}->execute(time(), $fileid);
}

=head2 C<filetimestamp ($fileid)>

C<filetimestamp> retrieves the time when the file
was parsed for references.

=over

=item 1 C<$fileid>

an I<integer> representing a file in the DB

=back

B<Requires:>

=over

=item * C<status_timestamp>

=back

=cut

sub filetimestamp {
# 	my ($self, $filename, $revision) = @_;
	my $self = shift @_;
	my ($fileid, $timestamp);
    
	$fileid = $self->fileidifexists(@_);
	if (defined($fileid)) {
		$self->{'status_timestamp'}->execute($fileid);
		$timestamp = $self->{'status_timestamp'}->fetchrow_array();
		$self->{'status_timestamp'}->finish();
	}
	return $timestamp;
}

=head2 C<symdeclarations ($symname, $releaseid)>

C<symdeclarations> returns an array containing the set of
declarations for the symbol in this release.

=over

=item 1 C<$symname>

the symbol name

=item 1 C<$releaseid>

the release (or version) containing the file

=back

B<Requires:>

=over

=item * C<definitions_select>

=back

=cut

sub symdeclarations {
# 	my ($self, $symname, $releaseid) = @_;
	my $self = shift @_;
	my (@ret, @row);

	$self->{'definitions_select'}->execute(@_);
	while (@row = $self->{'definitions_select'}->fetchrow_array) {
		$row[3] &&= $self->symname($row[3]); # convert the relsym symid
		push(@ret, [@row]);
	}
# opt	$self->{'definitions_select'}->finish();

	return @ret;
}

=head2 C<setsymdeclaration ($symname, $fileid, $line, $langid, $type, $relsym)>

C<setsymdeclaration> records a declaration in the DB.

=over

=item 1 C<$symname>

the symbol name

=item 1 C<$fileid>

the unique id which identifies a file AND a release

=item 1 C<$line>

the line number of the declaration

=item 1 C<$langid>

an I<integer> key for the language

=item 1 C<$type>

the type of the symbol

=item 1 C<$relsym>

an optional relation to some other symbol

=back

B<Requires:>

=over

=item * C<definitions_insert>

=back

=cut

sub setsymdeclaration {
	my ($self, $symname, $fileid, $line, $langid, $type, $relsym) = @_;

	my $sid = $self->symid($symname);
	$self->{'definitions_insert'}->execute
					( $sid, $fileid, $line, $langid, $type
					, $relsym ? $self->symid($relsym) : undef
					);
	if ($cntcache{$symname} < 0) {	# First incrementation?
		$cntcache{$symname} = 1 - $cntcache{$symname};
	} else {
		$cntcache{$symname} += 1;
	}
	if (defined($relsym)) {
		if ($cntcache{$relsym} < 0) {	# First incrementation?
			$cntcache{$relsym} = 1 - $cntcache{$relsym};
		} else {
			$cntcache{$relsym} += 1;
		}
	}
# die "Symbol cache not initialised for sym $symname\n" if (!defined($symcache{$symname}));
# die "Symbol cache not initialised for rel $relsym\n"
# 	if (defined($relsym) && !defined($symcache{$relsym}));
}

=head2 C<symreferences ($symname, $releaseid)>

C<symreferences> returns an array containing the set of
references to the symbol in this release.

=over

=item 1 C<$symname>

the symbol name

=item 1 C<$releaseid>

the release (or version) containing the file

=back

B<Requires:>

=over

=item * C<usages_select>

=back

=cut

sub symreferences {
# 	my ($self, $symname, $releaseid) = @_;
	my $self = shift @_;
	my (@ret, @row);

	$self->{'usages_select'}->execute(@_);
	while (@row = $self->{'usages_select'}->fetchrow_array) {
		push(@ret, [@row]);
	}
# opt	$self->{'usages_select'}->finish();

	return @ret;
}

=head2 C<setsymreference ($symname, $fileid, $line)>

C<setsymreference> records a reference in the database if the symbol
is already present (as a declaration).

=over

=item 1 C<$symname>

the symbol name

=item 1 C<$fileid>

the unique id which identifies a file AND a release

=item 1 C<$line>

the line number of the declaration

=back

B<Requires:>

=over

=item * C<symbols_byname>

=item * C<usages_insert>

=back

C<setsymreference> includes since release 1.0 part of C<issymbol>
so that this latter function is no longer needed when referencing files
and MUST NOT be used in C<referencefile> functions

=cut

sub setsymreference {
	my ($self, $symname, $fileid, $line) = @_;
	my $symid;
	my $symcount;

	if (!exists $symcache{$symname}) {
		$self->{'symbols_byname'}->execute($symname);
		($symid, $symcount) = $self->{'symbols_byname'}->fetchrow_array();
		if (defined($symid)) {
			$symcache{$symname} = $symid;
	# Do not negate $symcount since it will be incremented immediately
			$cntcache{$symname} = $symcount;
		} else {
	#	Since the symbol is not in the DB,
	#	it is safe to create a cache item to speed up
	#	future checks for the same symbol.
			$symcache{$symname} = undef;
			$cntcache{$symname} = 0;
			return;
		}
	} else {
		$symid = $symcache{$symname};
		return if !defined($symid);
	}
	$self->{'usages_insert'}->execute($fileid, $line, $symid);
	if ($cntcache{$symname} < 0) {	# First incrementation?
		$cntcache{$symname} = 1 - $cntcache{$symname};
	} else {
		$cntcache{$symname} += 1;
	}
# die "Symbol cache not initialised for $symname\n" if (!defined($symcache{$symname}));
}

=head2 C<issymbol ($symname, $releaseid)>

C<issymbol> returns I<true> (1) for an existing symbol in a given release
according to the DB,
I<false> (0) otherwise.

=over

=item 1 C<$symname>

the symbol name

=item 1 C<$releaseid>

the release (or version) containing the file

=back

B<Requires:>

=over

=item * C<symbols_byname>

=back

This functions is used during browsing to decide whether the symbol
should be highlighted or not.

Since release 1.0, this function is no longer used during the usage
collecting pass.
It can now have its own independent cache strategy, but it MUST NOT
be called outside the browsing pass.

=cut

# TODO: make full use of $releaseid (not present in symbols_byname)

sub issymbol {
	my ($self, $symname, $releaseid) = @_;
	my $symid;
	my $symcount;

	if (!exists $symcache{$symname}) {
		$self->{'symbols_byname'}->execute($symname);
		($symid, $symcount) = $self->{'symbols_byname'}->fetchrow_array();
		if (!defined($symid)) {
	#	Since the symbol is not in the DB,
	#	it is safe to create a cache item to speed up
	#	future checks for the same symbol.
# 		$symcache{$releaseid}{$symname} = $symid;
			$symcache{$symname} = undef;
			$cntcache{$symname} = 0;
		} else {
	#	Create a "positive" cache entry for future references.
			$symcache{$symname} = $symid;
			$cntcache{$symname} = $symcount;
		}
	} else {
# 	$symid = $symcache{$releaseid}{$symname};
		$symid = $symcache{$symname};
	}
	return defined($symid) ? 1 : 0;
}

=head2 C<symid ($symname)>

C<symid> returns a unique id for a symbol.

If symbol is unknown, insert it into the DB with a zero reference count.
The reference count is adjusted by the methods which add definition
or usage.
Decrementing the reference count is only done when purging the database.

=over

=item 1 C<$symname>

the symbol name

=back

B<Requires:>

=over

=item * C<symbols_byname>

=item * C<symbols_insert>

=back

=cut

# TODO: $releaseid?

sub symid {
	my ($self, $symname) = @_;
	my $symid;
	my $symcount;

	$symid = $symcache{$symname};
	unless (defined($symid)) {
		$self->{'symbols_byname'}->execute($symname);
		($symid, $symcount) = $self->{'symbols_byname'}->fetchrow_array();
		unless ($symid) {
			$symid = ++$symnum;
			$symcount = 0;
			$self->{'symbols_insert'}->execute($symname, $symid);
		}
		$symcache{$symname} = $symid;
		$cntcache{$symname} = -$symcount;
	}

	return $symid;
}

=head2 C<symname ($symid)>

C<symname> returns the symbol name from a symbol id.

=over

=item 1 C<$symid>

the unique id for a symbol

=back

B<Requires:>

=over

=item * C<symbols_byid>

=back

=cut

sub symname {
# 	my ($self, $symid) = @_;
	my $self = shift @_;
	my $symname;

	$self->{'symbols_byid'}->execute(@_);
	($symname) = $self->{'symbols_byid'}->fetchrow_array();

	return $symname;
}

=head2 C<decid ($lang, $string)>

C<decid> retrieves a unique id for a declaration type in a given
language. If this declaration is not yet in the DB, record it.

=over

=item 1 C<$lang>

the unique id for the language

=item 1 C<$string>

the text for the declaration (from C<{'typemap'}{letter}> in a
I<generic.conf> language description)

=back

B<Requires:>

=over

=item * C<langtypes_select>

=item * C<langtypes_insert>

=back

These records are in fact the text for the language types.

The text retrieval function is not implemented because it is
implictly done in the C<symdeclarations> query.

B<CAVEAT!>

=over

=item

I<This implementation is valid for DB engines with auto-incrementing
fields. It must be overridden when the auto-incrementation feature
is missing (e.g. PostgreSQL and SQLite).>

=back

=cut

sub decid {
# 	my ($self, $lang, $string) = @_;
	my $self = shift @_;
	my $declid;

	$self->{'langtypes_select'}->execute(@_);
	($declid) = $self->{'langtypes_select'}->fetchrow_array();
# opt	$self->{'langtypes_select'}->finish();
	unless (defined($declid)) {
		$declid = ++$typenum;
		$self->{'langtypes_insert'}->execute($declid, @_);
	}
# opt	$self->{'langtypes_select'}->finish();

	return $declid;
}

=head2 C<commit ()>

Commit the last set of operations and start a new transaction.

If transactions are not supported, it's OK for this to be a no-op.

=cut

sub commit {
	my $self = shift @_;
	$self->{dbh}->commit;
}

=head2 C<forcecommit ()>

Commit now the database, even if auto commit mode is in effect.

This method should not be overridden in specific drivers.

=cut

sub forcecommit {
	my $self = shift @_;

	my $oldcommitmode = $self->{dbh}{'AutoCommit'};
	$self->{dbh}{'AutoCommit'} = 0;
	$self->{dbh}->commit;
	$self->{dbh}{'AutoCommit'} = $oldcommitmode;
}

=head2 C<emptycache ()>

C<emptycache> empties the internal symbol cache.

This function should be called before parsing each new file.
If this is not done then too much memory will be used and
things will become very slow.

B<Note:>

=over

=item

I<With the implementation of> C<flushcache>I<, this function is
no longer necessary since the cache is also emptied in that
subroutine.>

=back

=cut

sub emptycache {
	%symcache = ();
	%cntcache = ();
}

=head2 C<flushcache ($full)>

C<flushcache> flushes the internal symbol cache.

=over

=item 1 C<$full>

optional argument to force 0-count write back

(When creating the database, reference counts are incremented.
Consequently, if the final count is still zero, the symbol has not
been referenced and there is no need to overwrite the record.
On the contrary, when purging the database, reference counts may
decrement to zero and it is then mandatory to update the record
so that it can later be purged or correctly updated.)

=back

This function should be called at the end of file processing.
It writes the cached symbol reference count into the appropriate
symbol records of the DB.

To minimize I/O, reference counts are negated when entered into
the cache. The counts are turned back positive when they need to be
incremented. Thus strictly positive values show which symbols have
been referenced. Only these are flushed to the DB.

The cache is then emptied

B<Requires:>

=over

=item * C<symbols_setref>

=back

=cut

sub flushcache {
	my ($self, $full) = @_;
	my $threshold = defined($full) && $full > 0
					? -1 : 0;

	for my $s (keys %symcache) {
		if ($cntcache{$s} > $threshold) {
			$self->{'symbols_setref'}->execute
				( $cntcache{$s}
				, $symcache{$s}
				);
		}
	}
	%symcache = ();
	%cntcache = ();
}

=head2 C<purgefile ($fid, $releaseid)>

C<purgefile> deletes data related to an obsoleted file in the DB.

Data associated to the designated file are erased from the tables.

=over

=item 1 C<$fid>

the unique id for a base revision file

=item 1 C<$releaseid>

the release (or version) containing the file

=back

B<Requires:>

=over

=item * C<related_symbols_select>

=item * C<delete_file_definitions>

=item * C<delete_file_usages>

=back

"Relation" symbol (from definitions) reference count must be
decremented first. After that, order of definitions/usages
deletion is irrelevant.

Symbols are not deleted when their reference count decrements to zero
because the same file (in a more recent version) is supposed to be
indexed soon: a majority of the symbols will be reentered again in
the database.

Release erasure is done in another sub since this erasure can occur
also when no definition/usage deletion is necessary.
The relevant code is thus written only once.

=cut

sub purgefile {
	my ($self, $fid, $releaseid) = @_;
	my ($symid, $symcount, $symname);
# NOTE:	For an obscure reason, it seems impossible to change
#		AutoCommit once a DBI/DBD method has been executed.
#		Consequently, the following explicit commits may give
#		warning messages if auto commit is still enabled.
#	What's upsetting is: no warnings are generated in purge!
	my $oldcommitmode = $self->{dbh}{'AutoCommit'};
	$self->{dbh}{'AutoCommit'} = 0;
	$self->{dbh}->commit;

# 	$self->{'related_symbols_select'}->execute($fid);
# 	while (($symid, $symcount, $symname)
# 			= $self->{'related_symbols_select'}->fetchrow_array()
# 		) {
# 		if (!exists($symcache{$symname})) {
# 			$symcache{$symname} = $symid;
# 			$cntcache{$symname} = $symcount;
# 		} else {
# 			if ($cntcache{$symname} < 0) {
# 				$cntcache{$symname} = -$cntcache{$symname};
# die "Inconsistent symbol reference count for $symname"
# 	if $symcount != $cntcache{$symname};
# 			}
# 		}
# 		$cntcache{$symname} = $symcount - 1
# 			if $cntcache{$symname} > 0;
# 	}
# # opt	$self->{'related_symbols_select'}->finish();
# 	$self->flushcache(1);
	$self->{'delete_file_definitions'}->execute($fid);
	$self->{'delete_file_usages'}->execute($fid);
	$self->{dbh}->commit;

	$self->{dbh}{'AutoCommit'} = $oldcommitmode;
}

=head2 C<purge ($releaseid)>

C<purge> selectively deletes data in the DB.

Data associated to a release are erased from the tables.

I<Order of erasure is critical to comply with foreign key constraints
between the different tables and to guarantee correctness of resulting
database structure.>

Once we know which base version files will be deleted,
I<definitions> and I<usages> in these files are erased,
which decrements symbol count.
The symbols with zero reference are deleted then.

After this step, no definition or usage are left pointing to the
candidate files. I<Releases> are deleted, decrementing the references
in I<status>. I<Status> with zero reference are then deleted
(I<files> cannot be deleted first because there is a "foreign key
contraint" on I<files> to I<status>).
I<Files> are implicitly deleted by a trigger from I<status> deletion.

=over

=item 1 C<$releaseid>

the target release (or version)

=back

B<Requires:>

=over

=item * C<delete_definitions>

=item * C<delete_usages>

=item * C<delete_symbols>

=item * C<delete_releases>

=item * C<delete_unused_status>

which should also delete I<files> table

=back

B<Note:>

=over

=item

DBD C<commit()> is explicitly called to bypass possible
disabling caused by private overriding method C<commit>.

=back

B<Todo:>

=over

=item

Manage the I<relid> relationship in I<definitions>

=back

=cut

sub purge {
	my ($self, $releaseid) = @_;
# NOTE:	For an obscure reason, it seems impossible to change
#		AutoCommit once a DBI/DBD method has been executed.
#		Consequently, the following explicit commits may give
#		warning messages if auto commit is still enabled.
#	What's upsetting is: no warnings are generated in purge!
	my $oldcommitmode = $self->{dbh}{'AutoCommit'};
	$self->{dbh}{'AutoCommit'} = 0;
	$self->{dbh}->commit;

	$self->{'delete_definitions'}->execute($releaseid);
	$self->{dbh}->commit;
	$self->{'delete_usages'}->execute($releaseid);
	$self->{dbh}->commit;
	$self->{'delete_symbols'}->execute();
	$self->{dbh}->commit;
	$self->{'delete_releases'}->execute($releaseid);
	$self->{dbh}->commit;
	$self->{'delete_unused_status'}->execute();
	$self->{dbh}->commit;

	$self->{dbh}{'AutoCommit'} = $oldcommitmode;
}

=head2 C<purgeall ()>

C<purgeall> deletes all data in the DB.

This is a brutal way of erasing everything, I<e.g.> for
C<--reindexall --allversions>.
It is much more efficient than a sequence of C<purge> on every version.

B<Requires:>

=over

=item * C<purge_all>

=back

=cut

sub purgeall {
	my ($self) = @_;

	$self->{'purge_all'}->execute();
}

=head2 C<uniquecountersreset ($force)>

C<uniquecountersreset> restarts the counters from 0.

=over

=item 1 C<$force>

an I<integer> used to force the C<$>I<xxx>C<ini> variables

If different from 0, this forces C<uniquecounterssave> to write
the reset values to the DB if immediately called after this method.

It is better to call the method a second time with argument 0 to
avoid any unforeseen side-effects, though there should be none.

=back

=cut

sub uniquecountersreset {
	my ($self, $force) = @_;
	$filenum = 0;
	$symnum = 0;
	$typenum = 0;
	$fileini = $force;
	$symini  = $force;
	$typeini = $force;
}

=head2 C<uniquecounterssave ()>

C<uniquecounterssave> stores in the DB the current values of the
file, symbol and type counters for later sessions.

=cut

sub uniquecounterssave {
	my	($self) = @_;

	$self->{dbh}{'AutoCommit'} = 0;
	my $prefix = $self->{'config'}{'dbprefix'};
	if ($filenum != $fileini) {
		my $fnnv =
			$self->{dbh}->prepare
				( "update ${prefix}filenum"
				. ' set fid = ?'
				. ' where rcd = 0'
				);
		$fnnv->execute($filenum);
		$fnnv = undef;
	}
	if ($symnum != $symini) {
		my $snnv =
			$self->{dbh}->prepare
				( "update ${prefix}symnum"
				. ' set sid = ?'
				. ' where rcd = 0'
			);
		$snnv->execute($symnum);
		$snnv = undef;
	}
	if ($typenum != $typeini) {
		my $tnnv =
			$self->{dbh}->prepare
				( "update ${prefix}typenum"
				. ' set tid = ?'
				. ' where rcd = 0'
				);
		$tnnv->execute($typenum);
		$tnnv = undef;
	}
}

=head2 C<dropuniversalqueries ()>

C<dropuniversalqueries> deactivates all "universal" query statement
to prevent annoying "Disconnect invalidates xx active statement handles ..."
messages from disturbing the end user.
Derived instances are responsible for killing their own queries.

Most are probably overkill since C<execure> or C<fetchrow_array> may
already have disactivated the statement.

Must be called before C<final_cleanup> before disconnecting.

=cut

sub dropuniversalqueries {
	my ($self) = @_;

	# Kill the universal statement handles (specific modules
	# are responsible for their own additions).
	$self->{'files_insert'} = undef;
	$self->{'files_select'} = undef;
	$self->{'allfiles_select'} = undef;
	$self->{'symbols_insert'} = undef;
	$self->{'symbols_byname'} = undef;
	$self->{'symbols_byid'} = undef;
	$self->{'symbols_setref'} = undef;
	$self->{'related_symbols_select'} = undef;
	$self->{'delete_symbols'} = undef;
	$self->{'definitions_insert'} = undef;
	$self->{'definitions_select'} = undef;
	$self->{'delete_file_definitions'} = undef;
	$self->{'delete_definitions'} = undef;
	$self->{'releases_insert'} = undef;
	$self->{'releases_select'} = undef;
	$self->{'delete_one_release'} = undef;
	$self->{'delete_releases'} = undef;
	$self->{'status_insert'} = undef;
	$self->{'status_select'} = undef;
	$self->{'status_update'} = undef;
	$self->{'status_timestamp'} = undef;
	$self->{'status_update_timestamp'} = undef;
	$self->{'delete_unused_status'} = undef;
	$self->{'usages_insert'} = undef;
	$self->{'usages_select'} = undef;
	$self->{'delete_file_usages'} = undef;
	$self->{'delete_usages'} = undef;
	$self->{'langtypes_insert'} = undef;
	$self->{'langtypes_select'} = undef;
	$self->{'langtypes_count'} = undef;
	$self->{'purge_all'} = undef;
}

=head2 C<final_cleanup ()>

C<final_cleanup> allows to execute last-minute actions on the database
and disconnects.

Must be called before C<Index> object disappears.

=cut

sub final_cleanup {
	my ($self) = @_;

	$self->commit();
	$self->dropuniversalqueries();
	$self->{dbh}->disconnect() or die "Disconnect failed: $DBI::errstr";
}

1;
