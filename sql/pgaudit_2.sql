RESET pgaudit.log;
RESET pgaudit.log_catalog;
RESET pgaudit.log_level;
RESET pgaudit.log_parameter;
RESET pgaudit.log_relation;
RESET pgaudit.log_statement;
RESET pgaudit.log_statement_once;
RESET pgaudit.role;

RESET pgaudit.log_parameter_for_role_based;
RESET pgaudit.roles_scope;

SELECT current_user \gset


-- Test 1
-- SESSION-BASED - Standard session-based audit 

SET pgaudit.log = 'write';
SET pgaudit.log_client = ON;
SET pgaudit.log_level = 'notice';



CREATE TABLE role_test
(
    id integer 
); -- not logged

SELECT * FROM role_test; -- not logged

INSERT INTO role_test values (1); -- logged session



-- Test 2
-- ROLE-BASED - new role-based (postgres superuser a member of all roles)
RESET pgaudit.log; -- not logged
CREATE USER roleuser1 password 'password'; -- not logged
SET pgaudit.roles_scope = 'roleuser1';  -- logged on set

SELECT * FROM role_test; -- logged role

-- Test 3
-- Superuser changes ROLE to less privileged
GRANT SELECT ON role_test TO roleuser1;  -- logged role
set role 'roleuser1';  -- logged role

SELECT * FROM role_test; -- logged role


-- Test 4
-- Non-logged Role - session auditing not impacted
\connect - :current_user
CREATE ROLE roleuser2 LOGIN password 'password';   -- not logged
ALTER ROLE roleuser2 SET pgaudit.log = 'write';  -- not logged
ALTER ROLE roleuser2 SET pgaudit.log_client = ON; -- not logged
ALTER ROLE roleuser2 SET pgaudit.log_level = 'warning'; -- not logged
ALTER ROLE roleuser2 SET pgaudit.roles_scope = 'roleuser1'; -- not logged
GRANT SELECT, INSERT ON role_test TO roleuser2; -- not logged

\connect - roleuser2

INSERT INTO role_test values (2); -- logged session
SELECT * FROM role_test; -- not logged

-- Test 5
-- Membership of Role in scope for auditing
\connect - :current_user
GRANT roleuser1 TO roleuser2; -- not logged

\connect - roleuser2

INSERT INTO role_test values (3); -- logged session (session takes precedence)
SELECT * FROM role_test; -- logged role




-- Test 6 & 7 - set-up
-- Security Definer & Parameters for role-based
\connect - :current_user

CREATE TABLE role_test2
(
	id INT
); -- not logged


CREATE TABLE role_test3
(
	id INT
); -- not logged

REVOKE roleuser1 from roleuser2; -- not logged
GRANT SELECT, INSERT ON role_test2 to roleuser2; -- not logged
GRANT INSERT ON role_test3 to roleuser2; -- not logged


ALTER ROLE roleuser2 SET pgaudit.log_parameter_for_role_based = ON; -- not logged
ALTER ROLE roleuser2 SET pgaudit.log = 'read'; -- not logged

CREATE FUNCTION roletest2_insert() RETURNS TRIGGER AS $$
BEGIN
 UPDATE role_test2
 SET id = id + 90
 WHERE id = new.id;

 RETURN new;
END $$ LANGUAGE plpgsql security definer; -- not logged

SET pgaudit.log_client = ON; -- not logged
SET pgaudit.log_level = 'notice'; -- not logged
SET pgaudit.roles_scope = 'roleuser1';  -- logged on set


CREATE TRIGGER roletest2_insert_trg
	AFTER INSERT ON role_test2
	FOR EACH ROW EXECUTE PROCEDURE roletest2_insert();  -- logged role




WITH CTE AS
(
	INSERT INTO role_test3 VALUES (1)
				   RETURNING id
)
INSERT INTO role_test2
SELECT id
  FROM cte; -- Logged role, insert and trigger based update

--Test 6 & 7 Execution
\connect - roleuser2

INSERT INTO role_test2 VALUES (2); -- initial insert not logged, trigger based update logged with parameter

INSERT INTO role_test3 VALUES(2);  -- not logged

SELECT * FROM role_test2;  -- logged session

\connect - :current_user
CREATE ROLE roleuser3 LOGIN password 'password'; -- not logged
GRANT SELECT, UPDATE ON role_test2 to roleuser3; -- not logged
ALTER FUNCTION roletest2_insert() OWNER TO roleuser3; -- not logged

ALTER ROLE roleuser2 SET pgaudit.log_parameter_for_role_based = OFF

--<sort out here - want to confirm that parameteres not logged on insert>
ALTER ROLE roleuser2 SET pgaudit.log = 'read, write'; -- not logged

\connect - roleuser2
INSERT INTO role_test2 VALUES (3); -- not logged <session logged without param>

WITH CTE AS
(
	INSERT INTO role_test3 VALUES (3)
				   RETURNING id
)
INSERT INTO role_test2
SELECT id
  FROM cte; 



--Test 8 - DO with security definer
\connect - :current_user
SET pgaudit.log_client = ON; -- not logged
SET pgaudit.log_level = 'notice'; -- not logged
SET pgaudit.roles_scope = 'roleuser1';  -- logged on set

CREATE FUNCTION roletest2_change(change_id int) RETURNS void AS $$
BEGIN
 UPDATE role_test2
  SET id = id + 1
  WHERE id = change_id;
END $$ LANGUAGE plpgsql security definer; -- logged role

DO $$ BEGIN PERFORM roletest2_change(91); END $$; -- logged role, DO, SELECT, EXECUTE, UPDATE


GRANT SELECT, INSERT, UPDATE ON role_test2 to roleuser2; -- logged role
ALTER FUNCTION roletest2_change(int) OWNER TO roleuser3; -- logged role



\connect - roleuser2
DO $$ BEGIN PERFORM roletest2_change(93); END $$; -- logged session for select


--Test 9 - Extension role based (order of execution)
\connect - :current_user
SET pgaudit.log_client = ON; -- not logged
SET pgaudit.log_level = 'notice'; -- not logged
ALTER SYSTEM SET pgaudit.roles_scope = 'roleuser1';  -- logged on set

ALTER EXTENSION pgaudit UPDATE; -- logged role

--Test 10 - Close Portal role based (order of execution)
CLOSE ALL;


ALTER ROLE roleuser2 SET pgaudit.roles_scope = 'roleuser2';
ALTER ROLE roleuser2 RESET pgaudit.log;


\connect - roleuser2;
select * from role_test; -- logged role



\connect - :current_user
DROP FUNCTION roletest2_insert();
DROP FUNCTION roletest2_change;
DROP TRIGGER roletest2_insert_trg on role_test2;

REVOKE roleuser1 from roleuser2;
REVOKE ALL ON TABLE role_test FROM roleuser1;
REVOKE ALL ON TABLE role_test FROM roleuser2;
REVOKE ALL ON TABLE role_test2 FROM roleuser2;
REVOKE ALL ON TABLE role_test3 FROM roleuser2;
REVOKE ALL ON TABLE role_test2 FROM roleuser3;
DROP USER roleuser1;
DROP USER roleuser2;
DROP USER roleuser3;
DROP TABLE public.role_test;
DROP TABLE public.role_test2;
DROP TABLE public.role_test3;
