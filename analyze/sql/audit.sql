drop database if exists audit_log;
drop role if exists audit_log_owner;

create role audit_log_owner;
create database with owner audit_log_owner;

set session authorization audit_log_owner;

create schema audit_log;

create table audit_log.session
(
    id bigint not null,
    constraint session_pk primary key (id)
)
