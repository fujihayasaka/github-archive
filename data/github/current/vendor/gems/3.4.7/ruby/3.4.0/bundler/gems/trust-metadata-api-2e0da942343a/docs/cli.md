# TMA CLI

This repo contains a lightweight CLI for interacting with the TMA server over the Twirp interface.

## Build

```
make bin/cli
```

## Examples

### Write

- Option 1: create with filename

```
bin/cli create-package-attestation --base-url=http://127.0.0.1:8080 --hmac-key=c --purl=pkg:npm/foo/bar@12.3.1 --bundle=test/data/sigstoreBundle.json
```

- Option 2: create with stdin

```
export bundle=$(<test/data/sigstoreBundle.json)
```

```
echo "$bundle" |  bin/cli create-package-attestation --base-url=http://127.0.0.1:8080 --hmac-key=c --purl=pkg:npm/foo/bar@12.3.20 --bundle=-
```

### Read

```
bin/cli get-package-attestations --base-url=http://127.0.0.1:8080 --hmac-key=b --purl=pkg:npm/foo/bar@12.3.1
```
