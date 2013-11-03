# -*- tab-width: 4 perl-indent-level: 4-*-
###############################
#
# $Id: Mysql.pm,v 1.35 2012/09/10 17:22:21 ajlittoz Exp $
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

package LXR::Index::Mysql;

$CVSID = '$Id: Mysql.pm,v 1.35 2012/09/10 17:22:21 ajlittoz Exp $ ';

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
								, {'AutoCommit' => 0}
								)
#	MySQL seems to be neutral vis-à-vis auto commit mode, though
#	a tiny improvement may show up with explicit commit (the
#	difference on the medium-sized test cases is difficult to
#	appreciate since it is within the measurement error).
		or fatal "Can't open connection to database: $DBI::errstr\n";

	$self->{'files_insert'} =
		$self->{dbh}->prepare
			( "insert into ${prefix}files"
			. " (filename, revision, fileid)"
			. " values (?, ?, NULL)"
			);

	$self->{'symbols_insert'} =
		$self->{dbh}->prepare
			( "insert into ${prefix}symbols"
			. " (symname, symid, symcount)"
			. " values ( ?, NULL, 0)"
			);

	$self->{'langtypes_insert'} =
		$self->{dbh}->prepare
			( "insert into ${prefix}langtypes"
			. " (typeid, langid, declaration)"
			. " values (NULL, ?, ?)"
			);

	$self->{'purge_all'} = $self->{dbh}->prepare
		( "call ${prefix}purgeall()"
		);

	return $self;
}

1;
