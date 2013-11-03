/*- -*- tab-width: 4 -*- -*/
/*-
 *	SQL template for creating PostgreSQL tables
 *	(C) 2012 A. Littoz
 *	$Id: initdb-p-template.sql,v 1.3 2013/01/11 12:08:48 ajlittoz Exp $
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
/*-	The following shell command sequence will succeed even if an
	individual command fails because the object exists or cannot
	be created. This is the reason to have many commands instead
	of a single psql invocation. -*/
/*--*/
/*--*/
/*@IF	%_createglobals% */
/*@XQT echo "Note: deletion of user below fails if it owns databases"*/
/*@XQT echo "      and other objects."*/
/*@XQT echo "      If you want to keep some databases, ignore the error"*/
/*@XQT echo "      Otherwise, manually delete the objects"*/
/*@XQT echo "      and relaunch this script."*/
/*@IF		%_dbuser%*/
/*@XQT echo "*** PostgreSQL - Creating global user %DB_user%"*/
/*@XQT dropuser   -U postgres %DB_user%*/
/*@XQT createuser -U postgres %DB_user% -d -P -R -S*/
/*@ENDIF		%_dbuser%*/
/*@ENDIF	%_createglobals% */
/*@IF	%_dbuseroverride% */
/*@XQT echo "*** PostgreSQL - Creating tree user %DB_tree_user%"*/
/*@XQT dropuser   -U postgres %DB_tree_user%*/
/*@XQT createuser -U postgres %DB_tree_user% -d -P -R -S*/
/*@ENDIF	%_dbuseroverride% */
/*--*/
/*--*/

/*-		Create databases under LXR user
		but it prevents from deleting user if databases exist
-*//*- to activate place "- * /" at end of line (without spaces) -*/
/*@IF	%_createglobals% && %_globaldb% */
/*@XQT echo "*** PostgreSQL - Creating global database %DB_name%"*/
/*@XQT dropdb   -U %DB_user% %DB_name%*/
/*@XQT createdb -U %DB_user% %DB_name%*/
/*@ENDIF*/
/*@IF	!%_globaldb% */
/*@IF		%_dbuseroverride% */
/*@XQT echo "*** PostgreSQL - Creating tree database %DB_name%"*/
/*@XQT dropdb   -U %DB_tree_user% %DB_name%*/
/*@XQT createdb -U %DB_tree_user% %DB_name%*/
/*@ELSE*/
/*-	When an overriding username is already known, %_dbuseroverride% is left
 *	equal to zero to prevent generating a duplicate user. We must however
 *	test the existence of %DB_tree_user% to operate under the correct
 *	DB owner. -*/
/*@XQT echo "*** PostgreSQL - Creating tree database %DB_name%"*/
/*@IF			%DB_tree_user% */
/*@XQT dropdb   -U %DB_tree_user% %DB_name%*/
/*@XQT createdb -U %DB_tree_user% %DB_name%*/
/*@ELSE*/
/*@XQT dropdb   -U %DB_user% %DB_name%*/
/*@XQT createdb -U %DB_user% %DB_name%*/
/*@ENDIF		%DB_tree_user% */
/*@ENDIF	%_dbuseroverride% */
/*@ENDIF !%_globaldb% */
/*- end of disable/enable comment -*/
/*--*/
/*--*/
/*-		Create databases under master user, usually postgres
		may be restricted by site rules
-*//*- to activate place "- * /" at end of line (without spaces)
/*@IF	%_createglobals% && %_globaldb% */
/*@XQT echo "*** PostgreSQL - Creating global database %DB_name%"*/
/*@XQT dropdb   -U postgres %DB_name%*/
/*@XQT createdb -U postgres %DB_name%*/
/*@ENDIF*/
/*@IF	!%_globaldb% */
/*@XQT echo "*** PostgreSQL - Creating tree database %DB_name%"*/
/*@XQT dropdb   -U postgres %DB_name%*/
/*@XQT createdb -U postgres %DB_name%*/
/*@ENDIF	!%_globaldb% */
/*- end of disable/enable comment -*/
/*--*/
/*--*/

/*@XQT echo "*** PostgreSQL - Configuring tables %DB_tbl_prefix% in database %DB_name%"*/
/*-		Create databases under LXR user
 *		but it prevents from deleting user if databases exist
 *
 * Note:
 *	When an overriding username is already known, %_dbuseroverride% is left
 *	equal to zero to prevent generating a duplicate user. We must however
 *	test the existence of %DB_tree_user% to register the correct DB owner.
 *
-*//*- to activate place "- * /" at end of line (without spaces) -*/
/*@IF	%_dbuseroverride% */
/*@XQT psql -q -U %DB_tree_user% %DB_name% <<END_OF_TABLES*/
/*@ELSE*/
/*@IF		%DB_tree_user% */
/*@XQT psql -q -U %DB_tree_user% %DB_name% <<END_OF_TABLES*/
/*@ELSE*/
/*@XQT psql -q -U %DB_user% %DB_name% <<END_OF_TABLES*/
/*@ENDIF		%DB_tree_user% */
/*@ENDIF	%_dbuseroverride% */
/*- end of disable/enable comment -*/
/*--*/
/*--*/
/*-		Create databases under master user, usually postgres
		may be restricted by site rules
-*//*- to activate place "- * /" at end of line (without spaces)
/*@XQT psql -q -U postgres %DB_name% <<END_OF_TABLES*/
/*- end of disable/enable comment -*/
drop sequence if exists %DB_tbl_prefix%filenum;
drop sequence if exists %DB_tbl_prefix%symnum;
drop sequence if exists %DB_tbl_prefix%typenum;
drop table    if exists %DB_tbl_prefix%files cascade;
drop table    if exists %DB_tbl_prefix%symbols cascade;
drop table    if exists %DB_tbl_prefix%definitions cascade;
drop table    if exists %DB_tbl_prefix%releases cascade;
drop table    if exists %DB_tbl_prefix%usages cascade;
drop table    if exists %DB_tbl_prefix%status cascade;
drop table    if exists %DB_tbl_prefix%langtypes cascade;

create sequence %DB_tbl_prefix%filenum cache 500;
create sequence %DB_tbl_prefix%symnum  cache 500;
create sequence %DB_tbl_prefix%typenum cache 10;


/* Base version of files */
/*	revision:	a VCS generated unique id for this version
				of the file
 */
create table %DB_tbl_prefix%files
	( fileid		int   not null primary key -- given by filenum
	, filename		bytea not null
	, revision		bytea not null
	, constraint %DB_tbl_prefix%uk_files
		unique		(filename, revision)
	);
create index %DB_tbl_prefix%filelookup
	on %DB_tbl_prefix%files
	using btree (filename);

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
create table %DB_tbl_prefix%status
	( fileid	int      not null primary key
	, relcount  int
	, indextime int
	, status	smallint not null
	, constraint %DB_tbl_prefix%fk_sts_file
		foreign key (fileid)
		references %DB_tbl_prefix%files(fileid)
-- 		on delete cascade
	);

/* The following trigger deletes no longer referenced files
 * (from releases), once status has been deleted so that
 * foreign key constrained has been cleared.
 */
drop function if exists %DB_tbl_prefix%erasefile();
create function %DB_tbl_prefix%erasefile()
	returns trigger
	language PLpgSQL
/*@IF	%_shell% */
	as \$\$
/*@ELSE*/
	as $$
/*@ENDIF	%_shell% */
		begin
			delete from %DB_tbl_prefix%files
				where fileid = old.fileid;
			return old;
		end;
/*@IF	%_shell% */
	\$\$;
/*@ELSE*/
	$$;
/*@ENDIF	%_shell% */

drop trigger if exists %DB_tbl_prefix%remove_file
	on %DB_tbl_prefix%status;
create trigger %DB_tbl_prefix%remove_file
	after delete on %DB_tbl_prefix%status
	for each row
	execute procedure %DB_tbl_prefix%erasefile();

/* Aliases for files */
/*	A base version may be known under several releaseids
	if it did not change in-between.
	fileid:		refers to base version
	releaseid:	"public" release tag
 */
create table %DB_tbl_prefix%releases
	( fileid    int   not null
	, releaseid bytea not null
	, constraint %DB_tbl_prefix%pk_releases
		primary key	(fileid,releaseid)
	, constraint %DB_tbl_prefix%fk_rls_fileid
		foreign key (fileid)
		references %DB_tbl_prefix%files(fileid)
	);

/* The following triggers maintain relcount integrity
 * in status table after insertion/deletion of releases
 */
drop function if exists %DB_tbl_prefix%increl();
create function %DB_tbl_prefix%increl()
	returns trigger
	language PLpgSQL
/*- $$ is causing trouble with sh because it is replaced
 *  by the process PID. It must then be quoted if the
 *  resulting file is intended to be executed as a script.
-*/
/*@IF	%_shell% */
	as \$\$
/*@ELSE*/
	as $$
/*@ENDIF	%_shell% */
		begin
			update %DB_tbl_prefix%status
				set relcount = relcount + 1
				where fileid = new.fileid;
			return new;
		end;
/*@IF	%_shell% */
	\$\$;
/*@ELSE*/
	$$;
/*@ENDIF	%_shell% */

drop trigger if exists %DB_tbl_prefix%add_release
	on %DB_tbl_prefix%releases;
create trigger %DB_tbl_prefix%add_release
	after insert on %DB_tbl_prefix%releases
	for each row
	execute procedure %DB_tbl_prefix%increl();

/* Note: a release is erased only when option --reindexall
 * is given to genxref; it is thus necessary to reset status
 * to cause reindexing, especially if the file is shared by
 * several releases
 */
drop function if exists %DB_tbl_prefix%decrel();
create function %DB_tbl_prefix%decrel()
	returns trigger
	language PLpgSQL
/*@IF	%_shell% */
	as \$\$
/*@ELSE*/
	as $$
/*@ENDIF	%_shell% */
		begin
			update %DB_tbl_prefix%status
				set	relcount = relcount - 1
/*-	Uncomment next line if you want to rescan a common file
	on next indexation by genxref -*/
-- 				,	status = 0
				where fileid = old.fileid
				and relcount > 0;
			return old;
		end;
/*@IF	%_shell%*/
	\$\$;
/*@ELSE*/
	$$;
/*@ENDIF	%_shell% */

drop trigger if exists %DB_tbl_prefix%remove_release
	on %DB_tbl_prefix%releases;
create trigger %DB_tbl_prefix%remove_release
	after delete on %DB_tbl_prefix%releases
	for each row
	execute procedure %DB_tbl_prefix%decrel();

/* Types for a language*/
/*	declaration:	provided by generic.conf
 */
create table %DB_tbl_prefix%langtypes
	( typeid		smallint     not null -- given by typenum
	, langid		smallint     not null
	, declaration	varchar(255) not null
	, constraint %DB_tbl_prefix%pk_langtypes
		primary key	(typeid, langid)
	);

/* Symbol name dictionary */
/*	symid:		unique symbol id for name
	symcount:	number of definitions and usages for this name
	symname:	symbol name
 */
create table %DB_tbl_prefix%symbols
	( symid		int   not null primary key -- given by symnum
	, symcount  int
	, symname	bytea not null
	, constraint %DB_tbl_prefix%uk_symbols
		unique (symname)
	);

/* The following function decrements the symbol reference count
 * (to be used in triggers).
 */
drop function if exists %DB_tbl_prefix%decsym();
create function %DB_tbl_prefix%decsym()
	returns trigger
	language PLpgSQL
/*@IF	%_shell% */
	as \$\$
/*@ELSE*/
	as $$
/*@ENDIF	%_shell% */
		begin
			update %DB_tbl_prefix%symbols
				set	symcount = symcount - 1
				where symid = old.symid
				and symcount > 0;
			return old;
		end;
/*@IF	%_shell% */
	\$\$;
/*@ELSE*/
	$$;
/*@ENDIF	%_shell% */

/* Definitions */
/*	symid:	refers to symbol name
	fileid and line define the location of the declaration
	langid:	language id
	typeid:	language type id
	relid:	optional id of the englobing declaration
			(refers to another symbol, not a definition)
 */
create table %DB_tbl_prefix%definitions
	( symid		int      not null
	, fileid	int      not null
	, line		int      not null
	, typeid	smallint not null
	, langid	smallint not null
	, relid		int
	, constraint %DB_tbl_prefix%fk_defn_symid
		foreign key (symid)
		references %DB_tbl_prefix%symbols(symid)
	, constraint %DB_tbl_prefix%fk_defn_fileid
		foreign key (fileid)
		references %DB_tbl_prefix%files(fileid)
-- 	, index (typeid, langid)
	, constraint %DB_tbl_prefix%fk_defn_type
		foreign key (typeid, langid)
		references %DB_tbl_prefix%langtypes (typeid, langid)
	, constraint %DB_tbl_prefix%fk_defn_relid
		foreign key (relid)
		references %DB_tbl_prefix%symbols(symid)
	);
create index %DB_tbl_prefix%i_definitions
	on %DB_tbl_prefix%definitions
	using btree (symid);

/* The following trigger maintains correct symbol reference count
 * after definition deletion.
 */
drop trigger if exists %DB_tbl_prefix%remove_definition
	on %DB_tbl_prefix%definitions;
create trigger %DB_tbl_prefix%remove_definition
	after delete on %DB_tbl_prefix%definitions
	for each row
	execute procedure %DB_tbl_prefix%decsym();

/* Usages */
create table %DB_tbl_prefix%usages
	( symid		int not null
	, fileid	int not null
	, line		int not null
	, constraint %DB_tbl_prefix%fk_use_symid
		foreign key (symid)
		references %DB_tbl_prefix%symbols(symid)
	, constraint %DB_tbl_prefix%fk_use_fileid
		foreign key (fileid)
		references %DB_tbl_prefix%files(fileid)
	);
create index %DB_tbl_prefix%i_usages
	on %DB_tbl_prefix%usages
	using btree (symid);

/* The following trigger maintains correct symbol reference count
 * after usage deletion.
 */
drop trigger if exists %DB_tbl_prefix%remove_usage
	on %DB_tbl_prefix%usages;
create trigger %DB_tbl_prefix%remove_usage
	after delete on %DB_tbl_prefix%usages
	for each row
	execute procedure %DB_tbl_prefix%decsym();

grant select on %DB_tbl_prefix%files       to public;
grant select on %DB_tbl_prefix%symbols     to public;
grant select on %DB_tbl_prefix%definitions to public;
grant select on %DB_tbl_prefix%releases    to public;
grant select on %DB_tbl_prefix%usages      to public;
grant select on %DB_tbl_prefix%status      to public;
grant select on %DB_tbl_prefix%langtypes   to public;
/*@XQT END_OF_TABLES*/

