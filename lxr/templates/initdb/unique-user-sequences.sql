/*- -*- tab-width: 4 -*- */
/*
 *	SQL template for user management of unique record numbers
 *	(C) 2013-2013 A. Littoz
 *	$Id: unique-user-sequences.sql,v 1.1 2013/11/17 15:33:55 ajlittoz Exp $
 *
 *	This template is intended to be included in other SQL templates
 *	and further customised by Perl script initdb-config.pl.
 *	It creates the tables for replacement of built-in auto increment
 *	fields as experiments showed a substantial performance boost.
 *	Explanation:
 *		LXR writes into the database only at genxref time and
 *		does this with massive insertion in a short period and
 *		nobody else than genxref ever writes to the DB (*).
 *		Consequently, playing with COMMIT frequency results in
 *		fewer I/O and higher processing speed.
 *	(*) If somebody fancies to try to write while genxref is active,
 *		this assertion is broken and the DB will become an unusable
 *		mess.
 *
 *	This strategy is incompatible with multi-threading if it is
 *	ever reconsidered.
 *
 *	The specific DB managers in Index/ must be adapted to the
 *	presence of these extra tables.
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
drop table if exists %DB_tbl_prefix%filenum;
drop table if exists %DB_tbl_prefix%symnum;
drop table if exists %DB_tbl_prefix%typenum;

create table %DB_tbl_prefix%filenum
	( rcd int primary key
	, fid int
	);
insert into %DB_tbl_prefix%filenum
	(rcd, fid) VALUES (0, 0);

create table %DB_tbl_prefix%symnum
	( rcd int primary key
	, sid int
	);
insert into %DB_tbl_prefix%symnum
	(rcd, sid) VALUES (0, 0);

create table %DB_tbl_prefix%typenum
	( rcd int primary key
	, tid int
	);
insert into %DB_tbl_prefix%typenum
	(rcd, tid) VALUES (0, 0);

