# attest-npm-publish

This action can be used to generate a signed npm [publish attestation][1].

### Inputs

See [action.yml](action.yml)

```yaml
- uses: ./.github/actions/attest-npm-publish
  with:
    # Path to the artifact serving as the subject of the attestation.
    subject-path:

    # Name of the npm package.
    package-name:

    # Version of the npm package.
    package-version:

    # Private key to use when signing the attestation. Should be a
    # base64-encoded ECDSA key in PEM format.
    private-key:
```

### Outputs

<!-- markdownlint-disable MD013 -->

| Name          | Description                                                    | Example                 |
| ------------- | -------------------------------------------------------------- | ----------------------- |
| `bundle-path` | Absolute path to the file containing the generated attestation | `/tmp/attestation.json` |

<!-- markdownlint-enable MD013 -->

Attestations are saved in the JSON-serialized [Sigstore bundle][2] format.

[1]: https://github.com/npm/attestation/tree/main/specs/publish/v0.1
[2]:
  https://github.com/sigstore/protobuf-specs/blob/main/protos/sigstore_bundle.proto
