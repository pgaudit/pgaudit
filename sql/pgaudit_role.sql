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

SELECT * FROM role_test; -- not audited

INSERT INTO role_test values (1); -- session audited



-- Test 2
-- ROLE-BASED - new role-based (postgres superuser a member of all roles)
RESET pgaudit.log; -- not audited
CREATE USER roleuser1 password 'password'; -- not audited
CREATE ROLE roleuser2 LOGIN password 'password';   -- not audited
SET pgaudit.roles_scope = 'roleuser1';  -- role-based audited on set

SELECT * FROM role_test; -- role-based audited

-- Test 3
-- Superuser changes ROLE to less privileged
GRANT SELECT ON role_test TO roleuser1;  -- role-based audited
GRANT SELECT ON role_test TO roleuser2;  -- role-based audited
set role 'roleuser1';  -- role-based audited

SELECT * FROM role_test; -- role-based audited

SET SESSION AUTHORIZATION 'roleuser2'; -- role-based audited

SELECT * FROM role_test; -- role-based audited


-- Test 4
-- Non-logged Role - session auditing not impacted
\connect - :current_user
ALTER ROLE roleuser2 SET pgaudit.log = 'write';  -- not audited
ALTER ROLE roleuser2 SET pgaudit.log_client = ON; -- not audited
ALTER ROLE roleuser2 SET pgaudit.log_level = 'warning'; -- not audited
ALTER ROLE roleuser2 SET pgaudit.roles_scope = 'roleuser1'; -- not audited
GRANT SELECT, INSERT ON role_test TO roleuser2; -- not audited



\connect - roleuser2

INSERT INTO role_test values (2); -- session audited
SELECT * FROM role_test; -- not audited

-- Test 5
-- Membership of Role in scope for auditing
\connect - :current_user
GRANT roleuser1 TO roleuser2; -- not audited

\connect - roleuser2

INSERT INTO role_test values (3); -- session audited (session takes precedence)
SELECT * FROM role_test; -- role-based audited




-- Test 6 & 7 - set-up
-- Security Definer & Parameters for role-based
\connect - :current_user

CREATE TABLE role_test2
(
	id INT
); -- not audited


CREATE TABLE role_test3
(
	id INT
); -- not audited

REVOKE roleuser1 from roleuser2; -- not audited
GRANT SELECT, INSERT ON role_test2 to roleuser2; -- not audited
GRANT INSERT ON role_test3 to roleuser2; -- not audited


ALTER ROLE roleuser2 SET pgaudit.log_parameter_for_role_based = ON; -- not audited
ALTER ROLE roleuser2 SET pgaudit.log = 'read'; -- not audited

CREATE FUNCTION roletest2_insert() RETURNS TRIGGER AS $$
BEGIN
 UPDATE role_test2
 SET id = id + 90
 WHERE id = new.id;

 RETURN new;
END $$ LANGUAGE plpgsql security definer; -- not audited

SET pgaudit.log_client = ON; -- not audited
SET pgaudit.log_level = 'notice'; -- not audited
SET pgaudit.roles_scope = 'roleuser1';  -- role-based audited on set


CREATE TRIGGER roletest2_insert_trg
	AFTER INSERT ON role_test2
	FOR EACH ROW EXECUTE PROCEDURE roletest2_insert();  -- role-based audited




WITH CTE AS
(
	INSERT INTO role_test3 VALUES (1)
				   RETURNING id
)
INSERT INTO role_test2
SELECT id
  FROM cte; -- role-based audit: insert and trigger-based update

--Test 6 & 7 Execution
\connect - roleuser2

INSERT INTO role_test2 VALUES (2); -- initial insert not audited, trigger-based update role-based audited with parameter

INSERT INTO role_test3 VALUES(2);  -- not audited

SELECT * FROM role_test2;  -- session audited


--Test 8 - no parameters
\connect - :current_user
CREATE ROLE roleuser3 LOGIN password 'password'; -- not audited
GRANT SELECT, INSERT, UPDATE ON role_test2 TO roleuser3; -- not audited
GRANT SELECT, INSERT on role_test3 TO roleuser2; -- not audited
ALTER FUNCTION roletest2_insert() OWNER TO roleuser3; -- not audited

ALTER ROLE roleuser2 SET pgaudit.log_parameter_for_role_based = OFF; -- not audited
ALTER ROLE roleuser2 SET pgaudit.log = 'read, write'; -- not audited

\connect - roleuser2
INSERT INTO role_test2 VALUES (3); -- session audited without param

WITH CTE AS
(
	INSERT INTO role_test3 VALUES (3)
				   RETURNING id
)
INSERT INTO role_test2
SELECT id
  FROM cte; -- session audited without param


--Test 9 - DO with security definer
\connect - :current_user
SET pgaudit.log_client = ON; -- not audited
SET pgaudit.log_level = 'notice'; -- not audited
SET pgaudit.roles_scope = 'roleuser1';  -- role-based audited on set

CREATE FUNCTION roletest2_change(change_id int) RETURNS void AS $$
BEGIN
 UPDATE role_test2
  SET id = id + 1
  WHERE id = change_id;
END $$ LANGUAGE plpgsql security definer; -- role-based audited

DO $$ BEGIN PERFORM roletest2_change(91); END $$; -- role-based audited: DO, SELECT, EXECUTE, UPDATE


GRANT SELECT, INSERT, UPDATE ON role_test2 to roleuser2; -- role-based audited
ALTER FUNCTION roletest2_change(int) OWNER TO roleuser3; -- role-based audited



\connect - roleuser2
DO $$ BEGIN PERFORM roletest2_change(93); END $$; -- session audit for select


--Test 10 - Extension role based (order of execution)
\connect - :current_user
SET pgaudit.log_client = ON; -- not audited
SET pgaudit.log_level = 'notice'; -- not audited
ALTER SYSTEM SET pgaudit.roles_scope = 'roleuser1';   -- not audited
SELECT pg_reload_conf(); -- not audited


ALTER EXTENSION pgaudit UPDATE; -- role-based audited

--Test 11 - Close Portal role based (order of execution)
CLOSE ALL; -- role-based audited

--Test 12 - user is one of role scope items
ALTER ROLE roleuser2 SET pgaudit.roles_scope = 'roleuser1, roleuser2'; -- role-based audited
ALTER ROLE roleuser2 RESET pgaudit.log; -- role-based audited


\connect - roleuser2;
select * from role_test; -- role-based audited



\connect - :current_user
DROP FUNCTION roletest2_insert CASCADE;
DROP FUNCTION roletest2_change;


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
ALTER SYSTEM SET pgaudit.roles_scope = '[none]';
SELECT pg_reload_conf(); 
