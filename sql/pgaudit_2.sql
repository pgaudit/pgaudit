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
-- SESSION-BASED

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
-- ROLE-BASED
RESET pgaudit.log;
CREATE USER roleuser1 password 'password'; -- not logged
SET pgaudit.roles_scope = 'roleuser1';  -- not logged 

SELECT * FROM role_test; -- logged role

-- Test 3
-- Superuser changes ROLE
GRANT SELECT ON role_test TO roleuser1;  -- logged role
set role 'roleuser1';  -- logged role

SELECT * FROM role_test; -- logged role


-- Test 4
-- Non-logged Role
\connect - :current_user
CREATE ROLE roleuser2 LOGIN password 'password';   -- not logged
ALTER ROLE roleuser2 SET pgaudit.log = 'write';  -- not logged
ALTER ROLE roleuser2 SET pgaudit.log_client = ON; 
ALTER ROLE roleuser2 SET pgaudit.log_level = 'warning';
ALTER ROLE roleuser2 SET pgaudit.roles_scope = 'roleuser1';
GRANT SELECT, INSERT ON role_test TO roleuser2;

\connect - roleuser2

INSERT INTO role_test values (2); -- logged session
SELECT * FROM role_test; -- not logged

-- Test 5
-- Member Role
\connect - :current_user
GRANT roleuser1 TO roleuser2;

\connect - roleuser2

INSERT INTO role_test values (3); -- logged session
SELECT * FROM role_test; -- logged role


-- Test 6
-- Security Definer
\connect - :current_user

CREATE TABLE role_test2
(
	id INT
);

CREATE TABLE role_test3
(
	id INT
);



CREATE FUNCTION roletest2_insert() RETURNS TRIGGER AS $$
BEGIN
 UPDATE role_test2
 SET id = id + 90
 WHERE id = new.id;

 RETURN new;
END $$ LANGUAGE plpgsql security definer;

ALTER FUNCTION roletest2_insert() OWNER TO roleuser1;

CREATE TRIGGER roletest2_insert_trg
	AFTER INSERT ON test2
	FOR EACH ROW EXECUTE PROCEDURE roletest2_insert();

CREATE FUNCTION roletest2_change(change_id int) RETURNS void AS $$
BEGIN
	UPDATE role_test2
	   SET id = id + 1
	 WHERE id = change_id;
END $$ LANGUAGE plpgsql security definer;
ALTER FUNCTION roletest2_change(int) OWNER TO roleuser2;


WITH CTE AS
(
	INSERT INTO role_test3 VALUES (1)
				   RETURNING id
)

INSERT INTO role_test2
SELECT id
  FROM cte;

DO $$ BEGIN PERFORM test2_change(91); END $$;

WITH CTE AS
(
	INSERT INTO test2 VALUES (37)
				   RETURNING id
)

\connect - :current_user
DROP FUNCTION roletest2_insert();


REVOKE roleuser1 from roleuser2;
REVOKE ALL ON TABLE role_test FROM roleuser1;
REVOKE ALL ON TABLE role_test FROM roleuser2;
DROP USER roleuser1;
DROP USER roleuser2;
DROP TABLE public.role_test;
DROP TABLE public.role_test2;
DROP TABLE public.role_test3;
