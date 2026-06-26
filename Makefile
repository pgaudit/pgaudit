MODULE_big = pgaudit
OBJS = pgaudit.o $(WIN32RES)

# The version in the control file is the source of truth
PGAUDIT_VERSION := $(shell grep default_version pgaudit.control | sed "s/.*'\(.*\)'/\1/")

EXTENSION = pgaudit
DATA = pgaudit--$(PGAUDIT_VERSION).sql pgaudit--1.7--$(PGAUDIT_VERSION).sql
PGFILEDESC = "pgAudit - An audit logging extension for PostgreSQL"

REGRESS = pgaudit
REGRESS_OPTS = --temp-config=$(top_srcdir)/contrib/pgaudit/pgaudit.conf

TAP_TESTS = 1

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = contrib/pgaudit
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif

EXTRA_INSTALL += contrib/pg_stat_statements
