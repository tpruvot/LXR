# -*- tab-width: 4 perl-indent-level: 4-*-
###############################
#
# $Id: Mysql.pm,v 1.39 2013/11/20 14:57:19 ajlittoz Exp $
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

$CVSID = '$Id: Mysql.pm,v 1.39 2013/11/20 14:57:19 ajlittoz Exp $ ';

use strict;
use DBI;
use LXR::Common;

our @ISA = ('LXR::Index');

sub new {
	my ($self, $config) = @_;

	$self = bless({}, $self);
	$self->{dbh} = DBI->connect	( $config->{'dbname'}
								, $config->{'dbuser'}
								, $config->{'dbpass'}
								, {'AutoCommit' => 0}
								)
#	MySQL seems to be neutral vis-à-vis auto commit mode, though
#	a tiny improvement may show up with explicit commit (the
#	difference on the medium-sized test cases is difficult to
#	appreciate since it is within the measurement error).
		or die "Can't open connection to database: $DBI::errstr\n";

	my $prefix = $config->{'dbprefix'};

#	MySQL may be run with its built-in unique record id management
#	mechanisms. There is only a small performance improvement
#	between the most efficient variant and user management.
#	Uncomment the desired management method:
#	- Variant U: common user management (in Index.pm)
#	- Variant A enabled: built-in with id retrieval through
#	-			record re-read
#	- Variant B enabled: built-in with id retrieval through 
#				last_insert_id() function (faster than variant A)
#	Variant B is recommended over variant A.

# CAUTION 1: must be consistent with DB table architecture
#	extra tables with variant U
#	autoincrement fields with variants A/B
# CAUTION 2: Only one of built-in A or B/user must be chosen
#			Comment out the unused ones.

	# Variant B
#B	$self->{'last_auto_val'} = 
#B		$self->{dbh}->prepare('select last_insert_id()');
	# End of variants

	# Variant A & B
#AB	$self->{'files_insert'} =
#AB		$self->{dbh}->prepare
#AB			( "insert into ${prefix}files"
#AB			. ' (filename, revision, fileid)'
#AB			. ' values (?, ?, NULL)'
#AB			);
#AB
#AB	$self->{'symbols_insert'} =
#AB		$self->{dbh}->prepare
#AB			( "insert into ${prefix}symbols"
#AB			. ' (symname, symid, symcount)'
#AB			. ' values ( ?, NULL, 0)'
#AB			);
#AB
#AB	$self->{'langtypes_insert'} =
#AB		$self->{dbh}->prepare
#AB			( "insert into ${prefix}langtypes"
#AB			. ' (typeid, langid, declaration)'
#AB			. ' values (NULL, ?, ?)'
#AB			);
	# End of variants

	$self->{'purge_all'} = $self->{dbh}->prepare
		( "call ${prefix}PurgeAll()"
		);

	# Variant U
	$self->uniquecountersinit($prefix);
	# The final $x_num will be saved in final_cleanup before disconnecting
	# End of variants

	return $self;
}

##### To activate MySQL built-in record id management,
##### uncomment the following block and choose one of
##### the A/B variants.
##### Check also final_cleanup()

# sub fileid {
# # 	my ($self, $filename, $revision) = @_;
# 	my $self = shift @_;
# 	my $fileid;
# 
# 	$fileid = $self->fileidifexists(@_);
# 	unless ($fileid) {
# 		$self->{'files_insert'}->execute(@_);
# 	# Variant B
# 		$self->{'last_auto_val'}->execute();
# 		($fileid) = $self->{'last_auto_val'}->fetchrow_array();
# 		$self->{'status_insert'}->execute($fileid, 0);
# 	# Variant A
# #A		$self->{'files_select'}->execute(@_);
# #A		($fileid) = $self->{'files_select'}->fetchrow_array();
# #A		$self->{'status_insert'}->execute(0);
# 	# End of variants
# # opt	$self->{'last_auto_val'}->finish();
# # 		$files{"$filename\t$revision"} = $fileid;
# 	}
# 	return $fileid;
# }
# 
# sub symid {
# 	my ($self, $symname) = @_;
# 	my $symid;
# 	my $symcount;
# 
# 	$symid = $LXR::Index::symcache{$symname};
# 	unless (defined($symid)) {
# 		$self->{'symbols_byname'}->execute($symname);
# 		($symid, $symcount) = $self->{'symbols_byname'}->fetchrow_array();
# 		unless ($symid) {
# 			$self->{'symbols_insert'}->execute($symname);
# #             # Get the id of the new symbol
# 	# Variant B
# 			$self->{'last_auto_val'}->execute();
# 			($symid) = $self->{'last_auto_val'}->fetchrow_array();
# 			$symcount = 0;
# 	# Variant A
# #A 			$self->{'symbols_byname'}->execute($symname);
# #A 			($symid, $symcount) = $self->{'symbols_byname'}->fetchrow_array();
# 	# End of variants
# 		}
# 		$LXR::Index::symcache{$symname} = $symid;
# 		$LXR::Index::cntcache{$symname} = -$symcount;
# 	}
# 	return $symid;
# }
# 
# sub decid {
# # 	my ($self, $lang, $string) = @_;
# 	my $self = shift @_;
# 	my $declid;
# 
# 	$self->{'langtypes_select'}->execute(@_);
# 	($declid) = $self->{'langtypes_select'}->fetchrow_array();
# 	unless (defined($declid)) {
# 		$self->{'langtypes_insert'}->execute(@_);
# 	# Variant B
# 		$self->{'last_auto_val'}->execute();
# 		($declid) = $self->{'last_auto_val'}->fetchrow_array();
# 	# Variant A
# #A 		$self->{'langtypes_select'}->execute(@_);
# #A 		($declid) = $self->{'langtypes_select'}->fetchrow_array();
# 	# End of variants
# 	}
# # opt	$self->{'last_auto_val'}->finish();
# 	return $declid;
# }

sub purgeall {
	my ($self) = @_;

	$self->{'purge_all'}->execute();
	# Variant U
	$self->uniquecountersreset(0);
	# End of variants
}

sub final_cleanup {
	my ($self) = @_;

	# Variant U
	$self->uniquecounterssave();
	# End of variants
	$self->commit();
	# Variant B
#B 	$self->{'last_auto_val'} = undef;
	# End of variants
	$self->dropuniversalqueries();
	$self->{dbh}->disconnect() or die "Disconnect failed: $DBI::errstr";
}

1;
