#!/bin/bash
set -e

# Test upgrading the extension from each prior version that has an upgrade script in the tree. The prior version is
# built from its release tag and installed and the extension is created at that version. Then the current tree is
# installed and the extension is updated. Finally a DDL statement is audited to make sure the event trigger functions
# resolve in the new library.

# Run a command and show the output only when it fails
quiet()
{
    local log=/tmp/pgaudit-upgrade.log

    if ! "$@" > "${log}" 2>&1; then
        cat "${log}"
        echo "command failed: $*" >&2
        exit 1
    fi
}

# Get the extension version from the control file on stdin
control_version()
{
    sed -n "s/default_version = '\(.*\)'/\1/p"
}

# Find the newest release tag with the specified extension version. The tag does not always match the version, e.g.
# 1.6.0 has version 1.6, so check the control file in each tag.
release_tag()
{
    local tag

    for tag in $(git -C /pgaudit tag --sort=-v:refname | grep -vE 'beta|rc'); do
        if [ "$(git -C /pgaudit show "${tag}:pgaudit.control" 2>/dev/null | control_version)" == "$1" ]; then
            echo "${tag}"
            return
        fi
    done

    echo "no release tag found for extension version $1 (are the tags fetched?)" >&2
    return 1
}

# Check that the installed extension version is as expected
check_version()
{
    local actual

    actual=$(psql -Atc "select extversion from pg_extension where extname = 'pgaudit'")

    if [ "${actual}" != "$1" ]; then
        echo "expected extension version $1 but found '${actual}'" >&2
        exit 1
    fi
}

# Nothing to test when there are no upgrade scripts, e.g. the first release for a PostgreSQL major version
if ! ls /pgaudit/pgaudit--*--*.sql >/dev/null 2>&1; then
    echo "no upgrade scripts to test"
    exit 0
fi

# Allow git to read the repository when it is owned by a different user
git config --global --add safe.directory /pgaudit

version=$(control_version < /pgaudit/pgaudit.control)

# Build the current version
quiet make -C /pgaudit clean all USE_PGXS=1

for file in /pgaudit/pgaudit--*--*.sql; do
    # Get the prior version from the upgrade script name, e.g. pgaudit--18.0--18.1.sql
    prior=$(basename "${file}" .sql)
    prior=${prior#pgaudit--}
    prior=${prior%%--*}
    tag=$(release_tag "${prior}")

    echo "> Test upgrade from ${prior} (tag ${tag}) to ${version}"

    # Build and install the prior version
    prior_dir=/tmp/pgaudit-${prior}
    rm -rf "${prior_dir}"
    mkdir "${prior_dir}"
    git -C /pgaudit archive "${tag}" | tar -x -C "${prior_dir}"
    quiet make -C "${prior_dir}" all USE_PGXS=1
    quiet sudo bash -c "PATH=${PATH?} make -C ${prior_dir} install USE_PGXS=1"

    # Create the extension at the prior version
    quiet ${PGBIN?}/pg_ctl -w start -D ${PGDATA?}
    psql -v ON_ERROR_STOP=1 -c "create extension pgaudit"
    check_version "${prior}"
    quiet ${PGBIN?}/pg_ctl -w stop -D ${PGDATA?}

    # Install the current version
    quiet sudo bash -c "PATH=${PATH?} make -C /pgaudit install USE_PGXS=1"

    # Update the extension to the current version
    quiet ${PGBIN?}/pg_ctl -w start -D ${PGDATA?}
    psql -v ON_ERROR_STOP=1 -c "alter extension pgaudit update"
    check_version "${version}"

    # Make sure DDL is audited with the updated extension
    output=$(psql -q -v ON_ERROR_STOP=1 -c "set pgaudit.log = 'ddl'" -c "set pgaudit.log_client = on" \
        -c "set pgaudit.log_level = notice" -c "create table upgrade_test (id int)" 2>&1)
    echo "${output}"

    if ! echo "${output}" | grep -q 'AUDIT: SESSION,.*,DDL,CREATE TABLE,TABLE,public.upgrade_test,'; then
        echo "DDL was not audited after the upgrade" >&2
        exit 1
    fi

    # Clean up for the next prior version
    psql -q -v ON_ERROR_STOP=1 -c "drop table upgrade_test" -c "drop extension pgaudit"
    quiet ${PGBIN?}/pg_ctl -w stop -D ${PGDATA?}
done
