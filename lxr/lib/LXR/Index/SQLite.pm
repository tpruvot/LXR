# -*- tab-width: 4 perl-indent-level: 4-*-
###############################
#
# $Id: SQLite.pm,v 1.6 2013/11/17 08:57:26 ajlittoz Exp $
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

$CVSID = '$Id: SQLite.pm,v 1.6 2013/11/17 08:57:26 ajlittoz Exp $ ';

use strict;
use DBI;
use LXR::Common;

our @ISA = ('LXR::Index');

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

	$self = bless({}, $self);
	$self->{dbh} = DBI->connect($config->{'dbname'})
	or die "Can't open connection to database: $DBI::errstr\n";
	my $prefix = $config->{'dbprefix'};
#	SQLite is forced into explicit commit mode as the medium-sized
#	test cases have shown a 40-times (!) performance improvement
#	over auto commit.
	$self->{dbh}{'AutoCommit'} = 0;

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

	$self->uniquecountersinit($prefix);
	# The final $x_num will be saved in final_cleanup before disconnecting

	return $self;
}

#
# LXR::Index API Implementation
#

sub purgeall {
	my ($self) = @_;

# Not really necessary, but nicer for debugging
	$self->uniquecountersreset(-1);
	$self->uniquecounterssave();
	$self->uniquecountersreset(0);

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

	$self->uniquecounterssave();
	$self->{dbh}->commit;
	$self->{'purge_definitions'} = undef;
	$self->{'purge_usages'} = undef;
	$self->{'purge_langtypes'} = undef;
	$self->{'purge_symbols'} = undef;
	$self->{'purge_releases'} = undef;
	$self->{'purge_status'} = undef;
	$self->{'purge_files'} = undef;
	$self->dropuniversalqueries();
	$self->{dbh}->disconnect() or die "Disconnect failed: $DBI::errstr";
}

1;
