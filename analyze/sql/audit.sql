-- Stop on error
\set ON_ERROR_STOP on

-- Make sure that errors are detected and not automatically rolled back
\set ON_ERROR_ROLLBACK off

drop database if exists pgaudit;
drop role if exists pgaudit_owner;
drop role if exists pgaudit_etl;
drop user if exists pgaudit;

create role pgaudit_owner;
create role pgaudit_etl;
create user pgaudit;
grant pgaudit_etl to pgaudit;

create database pgaudit with owner pgaudit_owner;

\c pgaudit

set session authorization pgaudit_owner;

create schema audit_log;
grant usage
   on schema audit_log
   to pgaudit_etl;

create table audit_log.session
(
    session_id text not null,
    process_id int not null,
    session_start_time timestamp with time zone not null,
    user_name text not null,
    application_name text,
    connection_from text,
    state text not null
        constraint session_state_ck check (state in ('ok', 'error')),

    constraint session_pk
        primary key (session_id)
);

grant select,
      insert,
      update
   on audit_log.session
   to pgaudit_etl;

-- create table audit_log.logon
-- (
--     id bigint not null,
--     session_id bigint not null,
--     constraint logon_pk primary key (id)
-- )

create table audit_log.log_event
(
    session_id text not null
        constraint logevent_sessionid_fk
            references audit_log.session (session_id),
    session_line_num numeric not null,
    log_time timestamp(3) with time zone not null,
    command text,
    error_severity text,
    sql_state_code text,
    virtual_transaction_id text,
    transaction_id int,
    message text,
    detail text,
    hint text,
    query text,
    query_pos integer,
    internal_query text,
    internal_query_pos integer,
    context text,
    location text,

    constraint logevent_pk
        primary key (session_id, session_line_num)
    -- constraint logevent_sessionid_sessionlinenum_unq
    --     unique (session_id, session_line_num)
);

grant select,
      insert
   on audit_log.log_event
   to pgaudit_etl;

create table audit_log.audit_statement
(
    session_id text not null
        constraint auditstatement_sessionid_fk
            references audit_log.session (session_id),
    statement_id numeric not null,
    state text not null default 'ok'
        constraint auditstatement_state_ck check (state in ('ok', 'error')),
    error_session_line_num bigint,

    constraint auditstatement_pk
        primary key (session_id, statement_id)
);

grant select,
      update (state, error_session_line_num),
      insert
   on audit_log.audit_statement
   to pgaudit_etl;

create table audit_log.audit_substatement
(
    session_id text not null,
    statement_id numeric not null,
    substatement_id numeric not null,
    statement text,
    parameter text[],

    constraint auditsubstatement_pk
        primary key (session_id, statement_id, substatement_id),
    constraint auditsubstatement_sessionid_statementid_fk
        foreign key (session_id, statement_id)
        references audit_log.audit_statement (session_id, statement_id)
);

grant select,
      insert
   on audit_log.audit_substatement
   to pgaudit_etl;

create table audit_log.audit_substatement_detail
(
    session_id text not null,
    statement_id numeric not null,
    substatement_id numeric not null,
    session_line_num numeric not null,
    audit_type text not null
        constraint auditsubstatementdetail_audittype_ck
            check (audit_type in ('session', 'object')),
    class text not null,
    command text not null,
    object_type text,
    object_name text,

    constraint auditsubstatementdetail_pk
        primary key (session_id, statement_id, substatement_id, session_line_num),
    constraint auditsubstatementdetail_sessionid_sessionlinenum_unq
        unique (session_id, session_line_num),
    constraint auditsubstatementdetail_sessionid_statementid_substatementid_fk
        foreign key (session_id, statement_id, substatement_id)
        references audit_log.audit_substatement (session_id, statement_id, substatement_id),
    constraint auditsubstatementdetail_sessionid_sessionlinenum_fk
        foreign key (session_id, session_line_num)
        references audit_log.log_event (session_id, session_line_num)
        deferrable initially deferred
);

grant select,
      insert
   on audit_log.audit_substatement_detail
   to pgaudit_etl;
