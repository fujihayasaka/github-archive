# Cert inspect tool

CLI for inspecting Fulcio cert extensions and DSSE payload predicates in `.sigstore` bundles.

This is useful when writing tests against the bundle and you need certain values, like `ExpiresAt` timestamps.

## Build

```
make bin/inspect
```

## Run

```
./bin/inspect test/data/sigstoreBundle-SLSA1Provenance.bundle.json
```
