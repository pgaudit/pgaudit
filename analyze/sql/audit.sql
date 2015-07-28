-- Stop on error
\set ON_ERROR_STOP on

-- Make sure that errors are detected and not automatically rolled back
\set ON_ERROR_ROLLBACK off

drop database if exists pgaudit;
drop role if exists audit_log_owner;

create role audit_log_owner;
create database pgaudit with owner audit_log_owner;

\c pgaudit
set session authorization audit_log_owner;

create schema audit_log;

create sequence audit_log.object_id_seq start with 1;

create table audit_log.session
(
    id bigint not null default nextval('audit_log.object_id_seq'),
    user_name text not null,
    process_id int not null,
    session_key text not null,
    session_start_time timestamp with time zone not null,
    database_name text,
    connection_from text,
    state text not null
        constraint session_state_ck check (state in ('ok', 'error')),

    constraint session_pk
        primary key (id),
    constraint session_processid_sessionkey_sessionstarttime_unq
        unique (process_id, session_key, session_start_time)
);

-- create table audit_log.logon
-- (
--     id bigint not null,
--     session_id bigint not null,
--     constraint logon_pk primary key (id)
-- )

create table audit_log.log_event
(
    session_id bigint not null
        constraint even_sessionid_fk
            references audit_log.session (id),
    session_line_num bigint not null,
    log_time timestamp(3) with time zone not null,
    command text,
    message text,
    query text,

    constraint logevent_pk
        primary key (session_id, session_line_num)
    -- constraint logevent_sessionid_sessionlinenum_unq
    --     unique (session_id, session_line_num)
);

create table audit_log.audit_event
(
    session_id bigint not null,
    session_line_num bigint not null,
    audit_type text not null
        constraint event_audittype_ck
            check (audit_type in ('s', 'o')),
    statement_id bigint not null
        constraint event_statementid_ck
            check (statement_id >= 1),
    substatement_id bigint not null
        constraint event_substatementid_ck
            check (substatement_id >= 1),
    class text not null,
    command text not null,
    object_type text,
    object_name text,
    statement text,
    parameter text[],

    constraint auditevent_pk
        primary key (session_id, session_line_num),
    constraint auditevent_sessionid_sessionlinenum_fk
        foreign key (session_id, session_line_num)
        references audit_log.log_event (session_id, session_line_num)
);
