# sigstore-proto

The `sigstore-proto` gem contains Ruby classes generated from the following protocol buffers:

* [sigstore/protobuf-specs](https://github.com/sigstore/protobuf-specs/tree/main/protos)
* [in-toto/attestation](https://github.com/in-toto/attestation/tree/main/protos/in_toto_attestation/v1)

## Why?

Why does this gem exist when [`sigstore_protobuf_specs`](https://rubygems.org/gems/sigstore_protobuf_specs) is available?

Unfortunately, the Sigstore-published version of this code has the following dependencies:

* `googleapis-common-protos-types`: `~> 1.18`
* `google-protobuf`: `~> 4.29, >= 4.29.3`

Which conflicts with the versions of these dependencies pinned in the monolith:

* `googleapis-common-protos-types`: `1.7.0`
* `google-protobuf`: `3.14.0.1.r907f12546`

To work around this, we're building our own version of this gem which is compatible with the dependencies in the monolith.

In addition, there is no published gem which contains the in-toto attestation messages so `sigstore-proto` also serves as a vehicle for delivering that code.

## Development

### Refreshing the Protocol Buffers

To refresh the local copies of the Sigstore and in-toto protobufs, update either the `SIGSTORE_SOURCE_REF` or `INTOTO_SOURCE_REF` values in the `Makefile` and run the following:

```
make all-protos
```

### Regenerate Ruby Code

To regenerate the Ruby code from the local protobufs run the following:

```
make generate-ruby
```

