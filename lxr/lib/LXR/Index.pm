# -*- tab-width: 4 -*-
###############################################
#
# $Id: Index.pm,v 1.20 2012/08/03 14:27:45 ajlittoz Exp $

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

###############################################

=head1 Index module

This module defines the abstract access methods to the database.
If needed, the methods are overridden in the specific modules.

=cut

package LXR::Index;

$CVSID = '$Id: Index.pm,v 1.20 2012/08/03 14:27:45 ajlittoz Exp $ ';

use LXR::Common;
use strict;

#
# Global variables
#
our (%files, %symcache);


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

I<<There used to be a second C<@args> argument which passed file
open-attributes (such as C<O_RDWR> or C<O_CREAT>) when the DB
made of a set of files.
This is no longer used.>

=back

The specific constructor is responsible for creating hash elements
in C<$self> containing "cooked" queries (meaning they have been
processed by C<prepare> DBD method.

They are mentioned by the I<Requires> paragraphs in the following
method descriptions.

=cut

sub new {
	my ($self, $dbname) = @_;
	my $index;
    
	%files        = ();
	%symcache     = ();    

	my $prefix;
	if (defined($config->{'dbprefix'})) {
		$prefix = $config->{'dbprefix'};
	} else {
		$prefix = "lxr_";
	}

	if ($dbname =~ m/^DBI:/i) {
		if ($dbname =~ m/^dbi:mysql:/i) {
			require  LXR::Index::Mysql;
			$index = LXR::Index::Mysql->new($dbname, $prefix);
		} elsif ($dbname =~ m/^dbi:Pg:/i) {
			require  LXR::Index::Postgres;
			$index = LXR::Index::Postgres->new($dbname, $prefix);
		} elsif ($dbname =~ m/^dbi:SQLite:/i) {
			require  LXR::Index::SQLite;
			$index = LXR::Index::SQLite->new($dbname, $prefix);
		} elsif ($dbname =~ m/^dbi:oracle:/i) {
			require  LXR::Index::Oracle;
			$index = LXR::Index::Oracle->new($dbname, $prefix);
		} else {
			die "Can't find database, $dbname";
		}
	} else {
		die "Can't find database, $dbname";
	}
	return $index;
}

#
# Generic implementation of this interface
#

=head2 C<fileid ($filename, $revision)>

C<getdir> returns a unique id for a file with a given revision.

=over

=item 1 C<$filename>

a I<string> containing the path relative to C<'sourceroot'>

=item 1 C<$revision>

the revision for the file

CAUTION: this is not a release id!
It is computed by method filerev in the Files classes.

=back

The result is used as an index between the different DB tables
to refer to the file.

B<Requires:>

=over

=item C<files_select>

=item C<files_insert>

=back

=cut

sub fileid {
	my ($self, $filename, $revision) = @_;
	my ($fileid);

	unless (defined($fileid = $files{"$filename\t$revision"})) {
		$self->{'files_select'}->execute($filename, $revision);
		($fileid) = $self->{'files_select'}->fetchrow_array();
		unless ($fileid) {
			$self->{'files_insert'}->execute($filename, $revision);
			$self->{'files_select'}->execute($filename, $revision);
			($fileid) = $self->{'files_select'}->fetchrow_array();
			$self->{'status_insert'}->execute($fileid, 0);
		}
		$files{"$filename\t$revision"} = $fileid;
		$self->{'files_select'}->finish();
	}
	return $fileid;
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

=item C<releases_select>

=item C<releases_insert>

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
	my ($self, $fileid, $releaseid) = @_;

	my $rows = $self->{'releases_select'}->execute($fileid + 0, $releaseid);
	$self->{'releases_select'}->finish();

	unless ($rows > 0) {
		$self->{'releases_insert'}->execute($fileid, $releaseid);
	}
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
	my ($status);

	$self->{'status_select'}->execute($fileid);
	$status = $self->{'status_select'}->fetchrow_array();
	$self->{'status_select'}->finish();

	return defined($status) && $status & 1;
}

=head2 C<setfileindexed ($fileid)>

C<setfileindexed> marks the file referred to by
C<$fileid> as being indexed.

=over

=item 1 C<$fileid>

an I<integer> representing a file in the DB

=back

B<Requires:>

=over

=item C<status_select>

=item C<status_insert>

=item C<status_update>

=back

=cut

sub setfileindexed {
	my ($self, $fileid) = @_;
	my ($status);

	$self->{'status_select'}->execute($fileid);
	$status = $self->{'status_select'}->fetchrow_array();
	$self->{'status_select'}->finish();

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

B<Note:>

=over

=item

I<A file must> always I<<be indexed before being parsed for
reference. Calling C<setfilereferenced> implicitly sets
C<fileindexed> as well.>

=back

B<Requires:>

=over

=item C<status_select>

=back

=cut

sub filereferenced {
	my ($self, $fileid) = @_;
	my ($status);

	$self->{'status_select'}->execute($fileid);
	$status = $self->{'status_select'}->fetchrow_array();
	$self->{'status_select'}->finish();

	return defined($status) && $status & 2;
}

=head2 C<setfileindexed ($fileid)>

C<setfilereferenced> marks the file referred to by
C<$fileid> as having been parsed for references.

=over

=item 1 C<$fileid>

an I<integer> representing a file in the DB

=back

B<Requires:>

=over

=item C<status_select>

=item C<status_insert>

=item C<status_update>

=back

=cut

sub setfilereferenced {
	my ($self, $fileid) = @_;
	my ($status);
    
	$self->{'status_select'}->execute($fileid);
	$status = $self->{'status_select'}->fetchrow_array();
	$self->{'status_select'}->finish();

	if (!defined($status)) {
		print STDERR "$fileid status not defined!\n";
		$self->{'status_insert'}->execute($fileid + 0, 2);
	} elsif (!($status & 2)) {
		$self->{'status_update'}->execute($status|2, $fileid);
	}
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

=item C<definitions_select>

=back

=cut

sub symdeclarations {
	my ($self, $symname, $releaseid) = @_;
	my ($rows, @ret, @row);

	$rows = $self->{'definitions_select'}->execute("$symname", "$releaseid");
	while (@row = $self->{'definitions_select'}->fetchrow_array) {
		$row[3] &&= $self->symname($row[3]); # convert the relsym symid
		push(@ret, [@row]);
	}
	$self->{'definitions_select'}->finish();

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

=item C<definitions_insert>

=back

=cut

sub setsymdeclaration {
	my ($self, $symname, $fileid, $line, $langid, $type, $relsym) = @_;

	$self->{'definitions_insert'}->execute($self->symid($symname),
	$fileid, $line, $langid, $type, $relsym ? $self->symid($relsym) : undef);
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

=item C<usages_select>

=back

=cut

sub symreferences {
	my ($self, $symname, $releaseid) = @_;
	my ($rows, @ret, @row);

	$rows = $self->{'usages_select'}->execute("$symname", "$releaseid");

	while (@row = $self->{'usages_select'}->fetchrow_array) {
		push(@ret, [@row]);
	}

	$self->{'usages_select'}->finish();

	return @ret;
}

=head2 C<setsymreference ($symname, $fileid, $line)>

C<setsymreference> records a reference in the DB.

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

=item C<usages_insert>

=back

=cut

sub setsymreference {
	my ($self, $symname, $fileid, $line) = @_;

	$self->{'usages_insert'}->execute($fileid, $line, $self->symid($symname));
}

=head2 C<issymbol ($symname, $releaseid)>

C<issymbol> returns a unique id for a symbol in a given release
if it exists in the DB, C<undef> otherwise.

=over

=item 1 C<$symname>

the symbol name

=item 1 C<$releaseid>

the release (or version) containing the file

=back

B<Requires:>

=over

=item C<symbols_byname>

=back

This functions is used to decide whether the symbol should be
highlighted or not.

=cut

# TODO: make full use of $releaseid (not present in symbols_byname)

sub issymbol {
	my ($self, $symname, $releaseid) = @_;
	my ($symid);

	$symid = $symcache{$releaseid}{$symname};
	unless (defined($symid)) {
		$self->{'symbols_byname'}->execute($symname);
		($symid) = $self->{'symbols_byname'}->fetchrow_array();
		$self->{'symbols_byname'}->finish();
		$symcache{$releaseid}{$symname} = $symid;
	}

	return $symid;
}

=head2 C<symid ($symname)>

C<symid> returns a unique id for a symbol.

If symbol is unknown, insert it into the DB.

=over

=item 1 C<$symname>

the symbol name

=back

B<Requires:>

=over

=item C<symbols_byname>

=item C<symbols_insert>

=back

=cut

# TODO: $releaseid?

sub symid {
	my ($self, $symname) = @_;
	my ($symid);

	$symid = $symcache{$symname};
	unless (defined($symid)) {
		$self->{'symbols_byname'}->execute($symname);
		($symid) = $self->{'symbols_byname'}->fetchrow_array();
		$self->{'symbols_byname'}->finish();
		unless ($symid) {
			$self->{'symbols_insert'}->execute($symname);

            # Get the id of the new symbol
			$self->{'symbols_byname'}->execute($symname);
			($symid) = $self->{'symbols_byname'}->fetchrow_array();
			$self->{'symbols_byname'}->finish();
		}
		$symcache{$symname} = $symid;
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

=item C<symbols_byid>

=back

=cut

sub symname {
	my ($self, $symid) = @_;
	my ($symname);

	$self->{'symbols_byid'}->execute($symid + 0);
	($symname) = $self->{'symbols_byid'}->fetchrow_array();
	$self->{'symbols_byid'}->finish();

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

=item C<langtypes_select>

=item C<langtypes_insert>

=back

These records are in fact the text for the language types.

The text retrieval function is not implemented because it is
implictly done in the C<symdeclarations> query.

=cut

sub decid {
	my ($self, $lang, $string) = @_;

	my $rows = $self->{'langtypes_select'}->execute($lang, $string);
	$self->{'langtypes_select'}->finish();

	unless ($rows > 0) {
		$self->{'langtypes_insert'}->execute($lang, $string);
	}

	$self->{'langtypes_select'}->execute($lang, $string);
	my $id = $self->{'langtypes_select'}->fetchrow_array();
	$self->{'langtypes_select'}->finish();

	return $id;
}

=head2 C<commit ()>

Commit the last set of operations and start a new transaction.

If transactions are not supported, it's OK for this to be a no-op.

=cut

sub commit {
	my ($self) = @_;
	$self->{dbh}->commit;
	$self->{dbh}->begin_work;
}

=head2 C<emptycache ()>

C<emptycache> flushes the internal symbol cache.

This function should be called before parsing each new file.
If this is not done then too much memory will be used and
things will become very slow.

=cut

sub emptycache {
	%symcache = ();
}

=head2 C<purge ($releaseid)>

C<purge> selectively deletes data in the DB.

Data associated to a release (all except symbols) are erased
from the tables.

Symbols are not deleted, because they might be used by other
versions.
We can end up with unused symbols,
but that doesn't cause any problems

=over

=item 1 C<$releaseid>

the target release (or version)

=back

B<Requires:>

=over

=item C<delete_definitions>

=item C<delete_usages>

=item C<delete_releases>

=item C<delete_unused_files>

which should also delete status table

=back

=cut

sub purge {
	my ($self, $releaseid) = @_;

	$self->{'delete_definitions'}->execute($releaseid);
	$self->{'delete_usages'}->execute($releaseid);
	$self->{'delete_releases'}->execute($releaseid);
	$self->{'delete_unused_files'}->execute();
}

=head2 C<purgeall>

C<purgeall> deletes all data in the DB.

This is a more extensive version of C<purge> aimed at
C<--reindexall --allversions> with VCSes
which do not manage versions very well (e.g. CVS).

=over

=item 1 C<$releaseid>

the target release (or version)

=back

B<Requires:>

=over

=item C<purge_langtypes>

=item C<purge_files>

=item C<purge_definitions>

=item C<purge_releases>

=item C<purge_status>

=item C<purge_symbols>

=item C<purge_usages>

=back

=cut

sub purgeall {
	my ($self) = @_;

	$self->{'purge_all'}->execute();
}

1;
