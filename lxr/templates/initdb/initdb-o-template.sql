/*- -*- tab-width: 4 -*- -*/
/*-
 *	SQL template for creating Oracle tables
 *	(C) 2012-2013 A. Littoz
 *	$Id: initdb-o-template.sql,v 1.4 2013/11/17 11:12:07 ajlittoz Exp $
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

/*@XQT echo "*** Oracle - Database creation (!!! untested !!!) ***" */
/*@XQT sqlplus <<END_OF_TABLES*/
-- ***
-- *** CAUTION -CAUTION - CAUTION ***
-- ***
-- *** This update has not been tested because
-- *** Oracle has a proprietary licence.
-- ***
-- *** However, the maintainer is quite confident for
-- *** the table structure and associated triggers.
-- *** There is a doubt about PurgeAll procedure
-- *** which must be executed as a single transaction with
-- *** constraints disabled.
-- *** (It was written with SQL syntax description only
-- *** without live checks.)
-- ***
-- *** If something goes wrong, report to the maintainer.
-- ***

-- This assumes you have a user '%DB_user%' set up already.

drop sequence if exists %DB_tbl_prefix%filenum;
drop sequence if exists %DB_tbl_prefix%symnum;
drop sequence if exists %DB_tbl_prefix%typenum;
drop table    if exists %DB_tbl_prefix%definitions;
drop table    if exists %DB_tbl_prefix%langtypes;
drop table    if exists %DB_tbl_prefix%usages;
drop table    if exists %DB_tbl_prefix%symbols;
drop table    if exists %DB_tbl_prefix%releases;
drop table    if exists %DB_tbl_prefix%status;
drop table    if exists %DB_tbl_prefix%files;

commit;

create sequence %DB_tbl_prefix%filenum
INCREMENT BY 1   
START WITH 1    
NOMAXVALUE       
NOMINVALUE       
CACHE 5          
NOORDER;         

create sequence %DB_tbl_prefix%symnum
INCREMENT BY 1   
START WITH 1    
NOMAXVALUE       
NOMINVALUE       
CACHE 5          
NOORDER;         

create sequence %DB_tbl_prefix%typenum
INCREMENT BY 1   
START WITH 1    
NOMAXVALUE       
NOMINVALUE       
CACHE 5          
NOORDER;         

commit;


/* Base version of files */
/*	revision:	a VCS generated unique id for this version
				of the file
 */
create table %DB_tbl_prefix%files
	( fileid	number -- given by filenum
	, filename	varchar2(255)
	, revision	varchar2(255)
	, constraint %DB_tbl_prefix%pk_files
		primary key (fileid)
	, constraint %DB_tbl_prefix%uk_files
		unique (filename, revision)
	);

create index %DB_tbl_prefix%filelookup
	on %DB_tbl_prefix%files(filename);

commit;

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
	( fileid	number not null
	, relcount  number
	, indextime number
	, status	number not null
	, constraint %DB_tbl_prefix%pk_status
		primary key (fileid)
	, constraint %DB_tbl_prefix%fk_sts_file
		foreign key (fileid)
		references %DB_tbl_prefix%files(fileid)
		on delete cascade
);

/* The following trigger deletes no longer referenced files
 * (from releases), once status has been deleted so that
 * foreign key constrained has been cleared.
 */
create or replace trigger %DB_tbl_prefix%remove_file
	after delete on %DB_tbl_prefix%status
	for each row
	begin
		delete from %DB_tbl_prefix%files
			where fileid = old.fileid;
	end;

commit;

/* Aliases for files */
/*	A base version may be known under several releaseids
	if it did not change in-between.
	fileid:		refers to base version
	releaseid:	"public" release tag
 */
create table %DB_tbl_prefix%releases
	( fileid	number
	, releaseid	varchar2(255)
	, constraint %DB_tbl_prefix%pk_releases
		primary key (fileid,releaseid)
	, constraint %DB_tbl_prefix%fk_rls_fileid
		foreign key (fileid)
		references %DB_tbl_prefix%files(fileid)
	);

/* The following triggers maintain relcount integrity
 * in status table after insertion/deletion of releases
 */
create or replace trigger %DB_tbl_prefix%add_release
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
create or replace trigger %DB_tbl_prefix%remove_release
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

commit;

/* Types */
/*	declaration:	provided by generic.conf
 */
create table %DB_tbl_prefix%langtypes
	( typeid		number NULL
	, langid		number NOT NULL
	, declaration	varchar2(255)
	, constraint %DB_tbl_prefix%pk_langtypes
		primary key (declid, langid)
	);

commit;

/* Symbol name dictionary */
/*	symid:		unique symbol id for name
 * 	symcount:	number of definitions and usages for this name
 *	symname:	symbol name
 */
create table %DB_tbl_prefix%symbols
	( symid		number
	, symcount	number
	, symname	varchar2(255)
	, constraint %DB_tbl_prefix%pk_symbols
		primary key (symid)
	, constraint %DB_tbl_prefix%uk_symbols
		unique (symnane)
	);

create index %DB_tbl_prefix%symlookup
	on %DB_tbl_prefix%files(symname);

/* The following function decrements the symbol reference count
 * for a definition
 * (to be used in triggers).
 */
create or replace procedure %DB_tbl_prefix%decdecl()
as
begin
	update %DB_tbl_prefix%symbols
		set	symcount = symcount - 1
		where symid = old.symid
		and symcount > 0;
	if old.relid is not null
	then update %DB_tbl_prefix%symbols
		set	symcount = symcount - 1
		where symid = old.relid
		and symcount > 0;
	end if;
end;

/* The following function decrements the symbol reference count
 * for a usage
 * (to be used in triggers).
 */
create or replace procedure %DB_tbl_prefix%decusage()
as
begin
	update %DB_tbl_prefix%symbols
		set	symcount = symcount - 1
		where symid = old.symid
		and symcount > 0;
end;

commit;

/* Definitions */
/*	symid:	refers to symbol name
 *  fileid and line define the location of the declaration
 *	langid:	language id
 *	typeid:	language type id
 *	relid:	optional id of the englobing declaration
 *			(refers to another symbol, not a definition)
 */
create table %DB_tbl_prefix%definitions
	( symid		number
	, fileid	number
	, line		number
	, typeid	number
	, langid	number
	, relid		number
	, constraint %DB_tbl_prefix%fk_defn_symid
		foreign key (symid)
		references %DB_tbl_prefix%symbols(symid)
	, constraint %DB_tbl_prefix%fk_defn_fileid
		foreign key (fileid)
		references %DB_tbl_prefix%files(fileid)
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
 */
create or replace trigger %DB_tbl_prefix%remove_definition
	after delete on %DB_tbl_prefix%definitions
	for each row
	execute procedure %DB_tbl_prefix%decdecl();

commit;

/* Usages */
create table %DB_tbl_prefix%usages
	( fileid	number
	, line		number
	, symid		number
	, constraint %DB_tbl_prefix%fk_use_symid
		foreign key (symid)
		references %DB_tbl_prefix%symbols(symid)
	, constraint %DB_tbl_prefix%fk_use_fileid
		foreign key (fileid)
		references %DB_tbl_prefix%files(fileid)
	);

create index %DB_tbl_prefix%i_usages
	on %DB_tbl_prefix%usage(symid);

/* The following trigger maintains correct symbol reference count
 * after usage deletion.
 */
create or replace trigger %DB_tbl_prefix%remove_usage
	after delete on %DB_tbl_prefix%usages
	for each row
	execute procedure %DB_tbl_prefix%decusage();

commit;

create or replace procedure %DB_tbl_prefix%PurgeAll ()
as
begin
	set transaction read write;
	set constraints all deferred;
	truncate table %DB_tbl_prefix%definitions;
	truncate table %DB_tbl_prefix%usages;
	truncate table %DB_tbl_prefix%langtypes;
	truncate table %DB_tbl_prefix%symbols;
	truncate table %DB_tbl_prefix%releases;
	truncate table %DB_tbl_prefix%status;
	truncate table %DB_tbl_prefix%files;
	commit;
end;
/


--grants

grant select                         on %DB_tbl_prefix%filenum     to %DB_user%;
grant select                         on %DB_tbl_prefix%symnum      to %DB_user%;
grant select                         on %DB_tbl_prefix%declnum     to %DB_user%;
grant select, insert, update, delete on %DB_tbl_prefix%definitions to %DB_user%;
grant select, insert, update, delete on %DB_tbl_prefix%usages      to %DB_user%;
grant select, insert, update, delete on %DB_tbl_prefix%symbols     to %DB_user%;
grant select, insert, update, delete on %DB_tbl_prefix%releases    to %DB_user%;
grant select, insert, update, delete on %DB_tbl_prefix%status      to %DB_user%;
grant select, insert, update, delete on %DB_tbl_prefix%files       to %DB_user%;
grant select, insert, update, delete on %DB_tbl_prefix%langtypes   to %DB_user%;

commit;

quit
/*@XQT END_OF_TABLES*/
