```
docker build --build-arg UID=$(id -u) --build-arg GID=$(id -g) -f Dockerfile.u20 -t pgaudit-test .

docker run -it -v  ~/Documents/Code/postgres/contrib/pgaudit:/pgaudit pgaudit-test /pgaudit/test/test.sh
```
