drop sequence %DB_tbl_prefix%filenum;
drop sequence %DB_tbl_prefix%symnum;
drop sequence %DB_tbl_prefix%declnum;
drop table    %DB_tbl_prefix%files cascade;
drop table    %DB_tbl_prefix%symbols cascade;
drop table    %DB_tbl_prefix%indexes cascade;
drop table    %DB_tbl_prefix%releases cascade;
drop table    %DB_tbl_prefix%usage cascade;
drop table    %DB_tbl_prefix%status cascade;
drop table    %DB_tbl_prefix%declarations cascade;

create sequence %DB_tbl_prefix%filenum cache 50;
create sequence %DB_tbl_prefix%symnum  cache 50;
create sequence %DB_tbl_prefix%declnum cache 10;

create table %DB_tbl_prefix%files
	( filename	varchar
	, revision	varchar
	, fileid		int
	, primary key	(fileid)
	, unique		(filename, revision)
	);

create table %DB_tbl_prefix%symbols
	( symname	varchar
	, symid		int
	, primary key	(symid)
	, unique		(symname)
	);

create table %DB_tbl_prefix%declarations
	( declid		smallint not null
	, langid		smallint not null
	, declaration	char(255) not null
	, primary key	(declid, langid)
	);

create table %DB_tbl_prefix%indexes
	( symid		int		references %DB_tbl_prefix%symbols
	, fileid	int		references %DB_tbl_prefix%files
	, line		int
	, langid	smallint not null
	, type		smallint not null
	, relsym	int		references %DB_tbl_prefix%symbols
	, foreign key	(langid, type)	references %DB_tbl_prefix%declarations (langid, declid)
	);

create table %DB_tbl_prefix%releases
	( fileid	int		references %DB_tbl_prefix%files
	, releaseid	varchar
	, primary key	(fileid,releaseid)
	);

create table %DB_tbl_prefix%usage
	( fileid	int		references %DB_tbl_prefix%files
	, line		int
	, symid		int		references %DB_tbl_prefix%symbols
	);

create table %DB_tbl_prefix%status
	( fileid	int		references %DB_tbl_prefix%files
	, status	smallint
	, primary key	(fileid)
	);

create index %DB_tbl_prefix%indexindex  on %DB_tbl_prefix%indexes using btree (symid);
create index %DB_tbl_prefix%symbolindex on %DB_tbl_prefix%symbols using btree (symname);
create index %DB_tbl_prefix%usageindex  on %DB_tbl_prefix%usage   using btree (symid);
create index %DB_tbl_prefix%filelookup  on %DB_tbl_prefix%files   using btree (filename);

grant select on %DB_tbl_prefix%files        to public;
grant select on %DB_tbl_prefix%symbols      to public;
grant select on %DB_tbl_prefix%indexes      to public;
grant select on %DB_tbl_prefix%releases     to public;
grant select on %DB_tbl_prefix%usage        to public;
grant select on %DB_tbl_prefix%status       to public;
grant select on %DB_tbl_prefix%declarations to public;
