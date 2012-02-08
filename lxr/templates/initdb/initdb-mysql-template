/* Read this into mysql with "\. initdb-mysql" when logged in as root
   to delete the old lxr database and create a new */ 

drop database if exists %DB_name%; 
create database %DB_name%; 
use %DB_name%;

/* symnum filenum */
create table %DB_tbl_prefix%files
	( filename        char(255) binary not null
	, revision        char(255) binary not null
	, fileid          int not null auto_increment
	, primary key     (fileid)
/*	, unique          (filename, revision) */
	);

create table %DB_tbl_prefix%symbols
	( symname         char(255) binary not null
	, symid           int not null auto_increment
	, primary key     (symid)
/*	, unique          (symname) */
	);

create table %DB_tbl_prefix%indexes
	( symid           int not null references %DB_tbl_prefix%symbols
	, fileid          int not null references %DB_tbl_prefix%files
	, line            int not null
	, langid          tinyint  not null references %DB_tbl_prefix%declarations
	, type            smallint not null references %DB_tbl_prefix%declarations
	, relsym          int          references %DB_tbl_prefix%symbols
	);

create table %DB_tbl_prefix%releases 
	( fileid          int not null references %DB_tbl_prefix%files
	, releaseid       char(255) binary not null
	, primary key     (fileid,releaseid)
	);

create table %DB_tbl_prefix%usage
	( fileid          int not null references %DB_tbl_prefix%files
	, line            int not null
	, symid           int not null references %DB_tbl_prefix%symbols
	);

create table %DB_tbl_prefix%status
	( fileid          int not null references %DB_tbl_prefix%files
	, status          tinyint not null
	, primary key     (fileid)
	);

create table %DB_tbl_prefix%declarations
	( declid          smallint not null auto_increment
	, langid          tinyint not null
	, declaration     char(255) not null
	, primary key     (declid, langid)
	);


create        index %DB_tbl_prefix%indexindex  on %DB_tbl_prefix%indexes (symid) ;
create unique index %DB_tbl_prefix%symbolindex on %DB_tbl_prefix%symbols (symname) ;
create        index %DB_tbl_prefix%usageindex  on %DB_tbl_prefix%usage (symid) ;
create        index %DB_tbl_prefix%filelookup  on %DB_tbl_prefix%files (filename);

grant all on %DB_name%.* to %DB_user%@localhost;
