-- This assumes you have a user 'lxr' set up already.

drop sequence lxr_filenum;
drop sequence lxr_symnum;
drop sequence lxr_declnum;
drop table    lxr_indexes;
drop table    lxr_declarations;
drop table    lxr_usage;
drop table    lxr_symbols;
drop table    lxr_releases;
drop table    lxr_status;
drop table    lxr_files;

commit;

create sequence lxr_filenum
INCREMENT BY 1   
START WITH 1    
NOMAXVALUE       
NOMINVALUE       
CACHE 5          
NOORDER;         

create sequence lxr_symnum
INCREMENT BY 1   
START WITH 1    
NOMAXVALUE       
NOMINVALUE       
CACHE 5          
NOORDER;         

create sequence lxr_declnum
INCREMENT BY 1   
START WITH 1    
NOMAXVALUE       
NOMINVALUE       
CACHE 5          
NOORDER;         

commit;

create table lxr_files ( 			
	filename	varchar2(250),
	revision	varchar2(250),
	fileid		number,
	constraint lxr_pk_files primary key (fileid)
);

alter table lxr_files add unique (filename, revision);

create index lxr_i_files on lxr_files(filename);

commit;

create table lxr_symbols (				
	symname		varchar2(250),
	symid		number,
	constraint pk_lxr_symbols primary key (symid)
);

alter table lxr_symbols add unique(symname);

commit;

create table lxr_declarations (
	declid		number NULL,
	langid		number NULL,
	declaration	varchar2(255),
	constraint pk_lxr_declarations primary key (declid)
);

commit;

create table lxr_indexes (
	symid		number,
	fileid		number,
	line		number,
	langid		number,
	type		number,
	relsym		number,
	constraint fk_lxr_indexes_symid foreign key (symid) references lxr_symbols(symid),
	constraint fk_lxr_indexes_fileid foreign key (fileid) references lxr_files(fileid),
	--constraint fk_lxr_indexes_langid foreign key (langid, type) references lxr_declarations(langid, declid),
	constraint fk_lxr_indexes_relsym foreign key (relsym) references lxr_symbols(symid)
);

create index lxr_i_indexes on lxr_indexes(symid);

commit;

create table lxr_releases (	
	fileid		number,
	releaseid		varchar2(250),
	constraint pk_lxr_releases primary key (fileid,releaseid),
	constraint fk_lxr_releases_fileid foreign key (fileid) references lxr_files(fileid)
);

commit;

create table lxr_status (
	fileid		number,
	status		number,
	constraint pk_lxr_status primary key (fileid),
	constraint fk_lxr_status_fileid foreign key (fileid) references lxr_files(fileid)
);

commit;

create table lxr_usage (
	fileid		number,
	line		number,
	symid		number,
	constraint fk_lxr_usage_fileid foreign key (fileid) references lxr_files(fileid),
	constraint fk_lxr_usage_symid foreign key (symid) references lxr_symbols(symid)
);

create index lxr_i_usage on lxr_usage(symid);


--grants

grant select                         on lxr_filenum        to lxr;
grant select                         on lxr_symnum         to lxr;
grant select                         on lxr_declnum         to lxr;
grant select, insert, update, delete on lxr_indexes        to lxr;
grant select, insert, update, delete on lxr_usage          to lxr;
grant select, insert, update, delete on lxr_symbols        to lxr;
grant select, insert, update, delete on lxr_releases       to lxr;
grant select, insert, update, delete on lxr_status         to lxr;
grant select, insert, update, delete on lxr_files          to lxr;
grant select, insert, update, delete on lxr_declarations   to lxr;

commit;

quit
