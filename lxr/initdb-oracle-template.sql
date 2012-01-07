-- This assumes you have a user '%DB_user%' set up already.

drop sequence %DB_tbl_prefix%filenum;
drop sequence %DB_tbl_prefix%symnum;
drop sequence %DB_tbl_prefix%declnum;
drop table    %DB_tbl_prefix%indexes;
drop table    %DB_tbl_prefix%declarations;
drop table    %DB_tbl_prefix%usage;
drop table    %DB_tbl_prefix%symbols;
drop table    %DB_tbl_prefix%releases;
drop table    %DB_tbl_prefix%status;
drop table    %DB_tbl_prefix%files;

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

create sequence %DB_tbl_prefix%declnum
INCREMENT BY 1   
START WITH 1    
NOMAXVALUE       
NOMINVALUE       
CACHE 5          
NOORDER;         

commit;

create table %DB_tbl_prefix%files
	( filename	varchar2(250)
	, revision	varchar2(250)
	, fileid	number
	, constraint %DB_tbl_prefix%pk_files primary key (fileid)
	);

alter table %DB_tbl_prefix%files add unique (filename, revision);

create index %DB_tbl_prefix%i_files on %DB_tbl_prefix%files(filename);

commit;

create table %DB_tbl_prefix%symbols
	( symname	varchar2(250)
	, symid		number
	, constraint pk_%DB_tbl_prefix%symbols primary key (symid)
	);

alter table %DB_tbl_prefix%symbols add unique(symname);

commit;

create table %DB_tbl_prefix%declarations
	( declid		number NULL
	, langid		number NULL
	, declaration	varchar2(255)
	, constraint pk_%DB_tbl_prefix%declarations primary key (declid)
	);

commit;

create table %DB_tbl_prefix%indexes
	( symid		number
	, fileid	number
	, line		number
	, langid	number
	, type		number
	, relsym	number
	, constraint fk_%DB_tbl_prefix%indexes_symid  foreign key (symid)  references %DB_tbl_prefix%symbols(symid)
	, constraint fk_%DB_tbl_prefix%indexes_fileid foreign key (fileid) references %DB_tbl_prefix%files(fileid)
	--, constraint fk_%DB_tbl_prefix%indexes_langid foreign key (langid, type) references %DB_tbl_prefix%declarations(langid, declid)
	, constraint fk_%DB_tbl_prefix%indexes_relsym foreign key (relsym) references %DB_tbl_prefix%symbols(symid)
	);

create index %DB_tbl_prefix%i_indexes on %DB_tbl_prefix%indexes(symid);

commit;

create table %DB_tbl_prefix%releases
	( fileid	number
	, releaseid	varchar2(250)
	, constraint pk_%DB_tbl_prefix%releases primary key (fileid,releaseid)
	, constraint fk_%DB_tbl_prefix%releases_fileid foreign key (fileid) references %DB_tbl_prefix%files(fileid)
	);

commit;

create table %DB_tbl_prefix%status
	( fileid	number
	, status	number
	, constraint pk_%DB_tbl_prefix%status primary key (fileid)
	, constraint fk_%DB_tbl_prefix%status_fileid foreign key (fileid) references %DB_tbl_prefix%files(fileid)
);

commit;

create table %DB_tbl_prefix%usage
	( fileid	number
	, line		number
	, symid		number
	, constraint fk_%DB_tbl_prefix%usage_fileid foreign key (fileid) references %DB_tbl_prefix%files(fileid)
	, constraint fk_%DB_tbl_prefix%usage_symid foreign key (symid) references %DB_tbl_prefix%symbols(symid)
	);

create index %DB_tbl_prefix%i_usage on %DB_tbl_prefix%usage(symid);


--grants

grant select                         on %DB_tbl_prefix%filenum      to %DB_user%;
grant select                         on %DB_tbl_prefix%symnum       to %DB_user%;
grant select                         on %DB_tbl_prefix%declnum      to %DB_user%;
grant select, insert, update, delete on %DB_tbl_prefix%indexes      to %DB_user%;
grant select, insert, update, delete on %DB_tbl_prefix%usage        to %DB_user%;
grant select, insert, update, delete on %DB_tbl_prefix%symbols      to %DB_user%;
grant select, insert, update, delete on %DB_tbl_prefix%releases     to %DB_user%;
grant select, insert, update, delete on %DB_tbl_prefix%status       to %DB_user%;
grant select, insert, update, delete on %DB_tbl_prefix%files        to %DB_user%;
grant select, insert, update, delete on %DB_tbl_prefix%declarations to %DB_user%;

commit;

quit
