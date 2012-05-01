/* Read this into mysql with "\. initdb-mysql" when logged in as root
   to delete the old lxr database and create a new */ 

-- drop database if exists %DB_name%; 
create database %DB_name%; 
use %DB_name%;

/* symnum filenum */
create table if not exists %DB_tbl_prefix%files
	( filename        varchar(255) binary not null
	, revision        varchar(255) binary not null
	, fileid          int not null auto_increment
	, primary key     (fileid)
	);

create table if not exists %DB_tbl_prefix%symbols
	( symname         varchar(255) binary not null
	, symid           int not null auto_increment
	, primary key     (symid)
	);

create table if not exists %DB_tbl_prefix%indexes
	( symid           int not null references %DB_tbl_prefix%symbols
	, fileid          int not null references %DB_tbl_prefix%files
	, line            smallint not null
	, langid          tinyint  not null references %DB_tbl_prefix%declarations
	, type            smallint not null references %DB_tbl_prefix%declarations
	, relsym          int          references %DB_tbl_prefix%symbols
	);

create table if not exists %DB_tbl_prefix%releases
	( fileid          int not null references %DB_tbl_prefix%files
	, releaseid       varchar(64) binary not null
	, primary key     (fileid,releaseid)
	);

create table if not exists %DB_tbl_prefix%usage
	( fileid          int not null references %DB_tbl_prefix%files
	, line            smallint not null
	, symid           int not null references %DB_tbl_prefix%symbols
	);

create table if not exists %DB_tbl_prefix%status
	( fileid          int not null references %DB_tbl_prefix%files
	, status          tinyint not null
	, primary key     (fileid)
	);

create table if not exists %DB_tbl_prefix%declarations
	( declid          smallint not null auto_increment
	, langid          tinyint not null
	, declaration     varchar(255) not null
	, primary key     (declid, langid)
	);


create        index %DB_tbl_prefix%filelookup  on %DB_tbl_prefix%files (filename);

create unique index %DB_tbl_prefix%symbolindex on %DB_tbl_prefix%symbols (symname);

create        index %DB_tbl_prefix%indexindex  on %DB_tbl_prefix%indexes (symid);
create        index %DB_tbl_prefix%relsym      on %DB_tbl_prefix%indexes (relsym);
create        index %DB_tbl_prefix%fileid      on %DB_tbl_prefix%indexes (fileid);

create        index %DB_tbl_prefix%usageindex  on %DB_tbl_prefix%usage (symid);

-- tables are huge, MYISAM allow delayed insert and reduce db size
ALTER TABLE %DB_tbl_prefix%symbols ENGINE = MYISAM;
ALTER TABLE %DB_tbl_prefix%indexes ENGINE = MYISAM;
ALTER TABLE %DB_tbl_prefix%usage ENGINE = MYISAM;

ALTER TABLE %DB_tbl_prefix%declarations ENGINE = MYISAM;
ALTER TABLE %DB_tbl_prefix%releases ENGINE = MYISAM;
ALTER TABLE %DB_tbl_prefix%status ENGINE = MYISAM;
ALTER TABLE %DB_tbl_prefix%files ENGINE = MYISAM;


-- permissions
grant all on %DB_name%.* to %DB_user%@localhost;

SET PASSWORD FOR %DB_user%@localhost = PASSWORD('foo');

