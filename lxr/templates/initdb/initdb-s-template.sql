/*- -*- tab-width: 4 -*- */
/*
 *	SQL template for creating MySQL tables
 *	(C) 2012-2013 A. Littoz
 *	$Id: initdb-s-template.sql,v 1.5 2013/11/17 15:33:55 ajlittoz Exp $
 *
 *	This template is intended to be customised by Perl script
 *	initdb-config.pl which creates a ready to use shell script
 *	to initialise the database with command:
 *		./custom.d/"customised result file name"
 *
 */

/* **************************************************************
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licences/>.
 * **************************************************************
-*/
/*--*/
/*--*/
/*@XQT echo "*** SQLite -  Configuring tables %DB_tbl_prefix% in database %DB_name%"*/
/*@XQT sqlite3 %DB_name% <<END_OF_TABLES*/
drop table if exists %DB_tbl_prefix%files;
drop table if exists %DB_tbl_prefix%symbols;
drop table if exists %DB_tbl_prefix%definitions;
drop table if exists %DB_tbl_prefix%releases;
drop table if exists %DB_tbl_prefix%usages;
drop table if exists %DB_tbl_prefix%status;
drop table if exists %DB_tbl_prefix%langtypes;

/*- Tables for unique ids management -*/
/*@ADD initdb/unique-user-sequences.sql*/

/* Base version of files */
/*	revision:	a VCS generated unique id for this version
				of the file
 */
create table %DB_tbl_prefix%files
	( fileid    int          not null primary key
	, filename  varchar(255) not null
	, revision  varchar(255) not null
	, constraint %DB_tbl_prefix%uk_files
		unique (filename, revision)
	);
create index %DB_tbl_prefix%filelookup
	on %DB_tbl_prefix%files(filename);

/* Status of files in the DB */
/*	fileid:		refers to base version
	relcount:	number of releases associated with base version
	indextime:	time when file was parsed for references
	status:		set of bits with the following meaning
		1	declaration have been parsed
		2	references have been processed
	Though this table could be merged with 'files',
	performance is improved with access to a very small item.
 */
/* Deletion of a record automatically removes the associated
 * base version files record.
 */
create table %DB_tbl_prefix%status
	( fileid    int     not null primary key
	, relcount  int
	, indextime int
	, status    tinyint not null
	, constraint %DB_tbl_prefix%fk_sts_file
		foreign key (fileid)
		references %DB_tbl_prefix%files(fileid)
-- 		on delete cascade
	);

/* The following trigger deletes no longer referenced files
 * (from releases), once status has been deleted so that
 * foreign key constrained has been cleared.
 */
drop trigger if exists %DB_tbl_prefix%remove_file;
create trigger %DB_tbl_prefix%remove_file
	after delete on %DB_tbl_prefix%status
	for each row
		begin
			delete from %DB_tbl_prefix%files
				where fileid = old.fileid;
		end;

/* Aliases for files */
/*	A base version may be known under several releaseids
	if it did not change in-between.
	fileid:		refers to base version
	releaseid:	"public" release tag
 */
create table %DB_tbl_prefix%releases 
	( fileid    int          not null
	, releaseid varchar(255) not null
	, constraint %DB_tbl_prefix%pk_releases
		primary key (fileid, releaseid)
	, constraint %DB_tbl_prefix%fk_rls_fileid
		foreign key (fileid)
		references %DB_tbl_prefix%files(fileid)
	);

/* The following triggers maintain relcount integrity
 * in status table after insertion/deletion of releases
 */
drop trigger if exists %DB_tbl_prefix%add_release;
create trigger %DB_tbl_prefix%add_release
	after insert on %DB_tbl_prefix%releases
	for each row
	begin
		update %DB_tbl_prefix%status
			set relcount = relcount + 1
			where fileid = new.fileid;
	end;
/* Note: a release is erased only when option --reindexall
 * is given to genxref; it is thus necessary to reset status
 * to cause reindexing, especially if the file is shared by
 * several releases
 */
drop trigger if exists %DB_tbl_prefix%remove_release;
create trigger %DB_tbl_prefix%remove_release
	after delete on %DB_tbl_prefix%releases
	for each row
	begin
		update %DB_tbl_prefix%status
			set	relcount = relcount - 1
/*-	Uncomment next line if you want to rescan a common file
	on next indexation by genxref -*/
-- 			,	status = 0
			where fileid = old.fileid
			and relcount > 0;
	end;

/* Types for a language */
/*	declaration:	provided by generic.conf
 */
create table %DB_tbl_prefix%langtypes
	( typeid       smallint         not null
	, langid       tinyint unsigned not null
	, declaration  varchar(255)     not null
	, constraint %DB_tbl_prefix%pk_langtypes
		primary key  (typeid, langid)
	);

/* Symbol name dictionary */
/*	symid:		unique symbol id for name
	symcount:	number of definitions and usages for this name
	symname:	symbol name
 */
create table %DB_tbl_prefix%symbols
	( symid		int          not null primary key
	, symcount	int
	, symname	varchar(255) not null unique
	);
create index %DB_tbl_prefix%symlookup
	on %DB_tbl_prefix%symbols(symname);

/* Definitions */
/*	symid, fileid and line define the location of the declaration
	langid:	language id
	typeid:	language type id
	relid:	optional id of the englobing declaration
			(refers to another symbol, not a definition)
 */
create table %DB_tbl_prefix%definitions
	( symid   int      not null
	, fileid  int      not null
	, line    int      not null
	, typeid  smallint not null
	, langid  tinyint unsigned not null
	, relid   int
	, constraint %DB_tbl_prefix%fk_defn_symid
		foreign key (symid)
		references %DB_tbl_prefix%symbols(symid)
	, constraint %DB_tbl_prefix%fk_defn_fileid
		foreign key (fileid)
		references %DB_tbl_prefix%files(fileid)
-- 	, index (typeid, langid)
	, constraint %DB_tbl_prefix%fk_defn_type
		foreign key (typeid, langid)
		references %DB_tbl_prefix%langtypes(typeid, langid)
	, constraint %DB_tbl_prefix%fk_defn_relid
		foreign key (relid)
		references %DB_tbl_prefix%symbols(symid)
	);
create index %DB_tbl_prefix%i_definitions
	on %DB_tbl_prefix%definitions(symid);

/* The following trigger maintains correct symbol reference count
 * after definition deletion.
 * CAUTION: the code is duplicated below and must be kept identical
 */
drop trigger if exists %DB_tbl_prefix%remove_definition;
create trigger %DB_tbl_prefix%remove_definition
	after delete on %DB_tbl_prefix%definitions
	for each row
	begin
		update %DB_tbl_prefix%symbols
			set	symcount = symcount - 1
			where symid = old.symid
			and symcount > 0;
		update %DB_tbl_prefix%symbols
			set	symcount = symcount - 1
			where symid = old.relid
			and symcount > 0
			and old.relid is not null;
	end;

/* Usages */
create table %DB_tbl_prefix%usages
	( symid   int not null
	, fileid  int not null
	, line    int not null
	, constraint %DB_tbl_prefix%fk_use_symid
		foreign key (symid)
		references %DB_tbl_prefix%symbols(symid)
	, constraint %DB_tbl_prefix%fk_use_fileid
		foreign key (fileid)
		references %DB_tbl_prefix%files(fileid)
	);
create index %DB_tbl_prefix%i_usages
	on %DB_tbl_prefix%usages(symid);

/* The following trigger maintains correct symbol reference count
 * after usage deletion.
 * CAUTION: the code is duplicated above and must be kept identical
 */
drop trigger if exists %DB_tbl_prefix%remove_usage;
create trigger %DB_tbl_prefix%remove_usage
	after delete on %DB_tbl_prefix%usages
	for each row
	begin
		update %DB_tbl_prefix%symbols
			set	symcount = symcount - 1
			where symid = old.symid
			and symcount > 0;
	end;
/*@XQT END_OF_TABLES*/

