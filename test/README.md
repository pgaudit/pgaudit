```
docker run -it -u postgres -v ~/pgaudit:/pgaudit pgaudit-test bash -cl " \
    make -C /pgaudit install USE_PGXS=1 && \
    pg_ctl -D /var/lib/pgsql/14/data -w start && \
    make -C /pgaudit installcheck USE_PGXS=1"
```
