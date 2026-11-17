# Testing

Testing is performed using a Docker container. First build the container:
```
docker build --build-arg UID=$(id -u) --build-arg GID=$(id -g) -f test/Dockerfile.debian -t pgaudit-test .
```
or
```
docker build --build-arg UID=$(id -u) --build-arg GID=$(id -g) -f test/Dockerfile.rhel -t pgaudit-test .
```
Then run the test:
```
docker run --rm -v $(pwd):/pgaudit pgaudit-test /pgaudit/test/test.sh
```

## Upgrade Test

The upgrade test builds each prior version that has an upgrade script in the tree from its release tag, creates the extension at that version, then installs the current tree and updates the extension. The release tags must be present in the clone so run `git fetch --tags` first if needed. Then run the upgrade test:
```
docker run --rm -v $(pwd):/pgaudit pgaudit-test /pgaudit/test/test-upgrade.sh
```
