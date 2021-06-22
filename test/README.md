```
docker run -it -u postgres --name pgaudit-test -h pgaudit-test -v ..:/pgaudit bash -c " \
    make -C /pgaudit install USE_PGXS=1 && \
    pg_ctl -D /var/lib/pgsql/${PG_VERSION?}/data -w start && \
    make -C /pgaudit installcheck USE_PGXS=1"
```
