# docker build -t pgaudit-test .
FROM centos:7

# Setup environment
ENV PG_VERSION=14
ENV PATH="$PATH:/usr/pgsql-${PG_VERSION}/bin"

# Install Tools
RUN yum install -y centos-release-scl-rh epel-release
RUN yum install -y postgresql${PG_VERSION?}-devel make gcc openssl-devel llvm-toolset-7-clang llvm5.0 sudo

# Install PostgreSQL
RUN rpm --import http://yum.postgresql.org/RPM-GPG-KEY-PGDG
RUN rpm -ivh https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm
# Enable PG14 repo (can be removed after the official release)
RUN yum install -y yum-utils && yum-config-manager --enable pgdg14-updates-testing
RUN yum install -y postgresql${PG_VERSION?}-server

# Create PostgreSQL cluster
RUN sudo -u postgres /usr/pgsql-${PG_VERSION?}/bin/initdb -A trust -k /var/lib/pgsql/${PG_VERSION?}/data
RUN echo "shared_preload_libraries = 'pgaudit'" >> /var/lib/pgsql/${PG_VERSION?}/data/postgresql.conf
