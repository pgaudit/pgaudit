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

create table audit_log.session
(
    id bigint not null,
    timestamp timestamp(3) with time zone not null,
    logon text not null,
    process_id int not null,
    session_key text not null,

    constraint session_pk primary key (id)
);

-- create table audit_log.logon
-- (
--     id bigint not null,
--     session_id bigint not null,
--     constraint logon_pk primary key (id)
-- )

create table audit_log.event
(
    session_id bigint not null,
    timestamp timestamp(3) with time zone not null,
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
    parameter text[]
);
