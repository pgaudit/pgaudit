-- Stop on error
\set ON_ERROR_STOP on

-- Make sure that errors are detected and not automatically rolled back
\set ON_ERROR_ROLLBACK off

drop database if exists audit_test;
drop role if exists pgaudit_owner;
drop role if exists pgaudit_etl;
drop user if exists pgaudit;

create role pgaudit_owner;
create role pgaudit_etl;
create user pgaudit;
grant pgaudit_etl to pgaudit;

create database audit_test;

\c audit_test

create schema pgaudit authorization pgaudit_owner;

grant usage
   on schema pgaudit
   to pgaudit_etl;

set session authorization pgaudit_owner;

create table pgaudit.session
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

create or replace function pgaudit.session_insert()
    returns trigger as $$
-- declare
--     tsLastLogonTime timestamp with time zone;
--     tsCurrentLogonTime timestamp with time zone;
--     iLogonFailureTotal int;
begin
    -- select last_logon_time,
    --        current_logon_time,
    --        logon_failure_total
    --   into tsLastLogonTime,
    --        tsCurrentLogonTime,
    --        iLogonFailureTotal
    --   from pgaudit.logon
    --  where user_name = new.user_name;

    update pgaudit.logon
       set last_logon_time = case when new.state = 'ok' then new.session_start_time else last_logon_time end,
           logon_failure_total = case when new.state = 'ok' then 0 else logon_failure_total + 1 end
     where user_name = new.user_name;

    if not found then
        insert into pgaudit.logon (user_name, last_logon_time, logon_failure_total)
                           values (new.user_name,
                                   case when new.state = 'ok' then new.session_start_time else null end,
                                   case when new.state = 'ok' then 0 else 1 end);
    end if;

    return new;
end
$$ language plpgsql security definer;

create trigger session_trigger_insert
    after insert on pgaudit.session
    for each row execute procedure pgaudit.session_insert();

grant select,
      insert,
      update (application_name)
   on pgaudit.session
   to pgaudit_etl;

create table pgaudit.logon
(
     user_name text not null,
     last_logon_time timestamp with time zone,
     logon_failure_total int not null,

     constraint logon_pk
        primary key (user_name)
);

create or replace function pgaudit.logon_info()
    returns table
(
    last_logon_time timestamp with time zone,
    logon_failures_since_last_logon int
)
    as $$
begin
    return query
    (
        select last_logon_time,
               logon_failure_total
          from logon
         where user_name = session_user
    );
end
$$ language plpgsql security definer;

grant execute on function pgaudit.logon_info() to public;

create table pgaudit.log_event
(
    session_id text not null
        constraint logevent_sessionid_fk
            references pgaudit.session (session_id),
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
   on pgaudit.log_event
   to pgaudit_etl;

create table pgaudit.audit_statement
(
    session_id text not null
        constraint auditstatement_sessionid_fk
            references pgaudit.session (session_id),
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
   on pgaudit.audit_statement
   to pgaudit_etl;

create table pgaudit.audit_substatement
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
        references pgaudit.audit_statement (session_id, statement_id)
);

grant select,
      insert
   on pgaudit.audit_substatement
   to pgaudit_etl;

create table pgaudit.audit_substatement_detail
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
        references pgaudit.audit_substatement (session_id, statement_id, substatement_id),
    constraint auditsubstatementdetail_sessionid_sessionlinenum_fk
        foreign key (session_id, session_line_num)
        references pgaudit.log_event (session_id, session_line_num)
        deferrable initially deferred
);

grant select,
      insert
   on pgaudit.audit_substatement_detail
   to pgaudit_etl;
