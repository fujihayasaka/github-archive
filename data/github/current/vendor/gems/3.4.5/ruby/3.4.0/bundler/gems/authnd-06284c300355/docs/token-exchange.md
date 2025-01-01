# Stateless Token Exchange

### Context

The `TokenExchanger` service supports exchanging an access token (i.e. s2s, u2s, oauth, PAT) for a ECDSA-P256 signed JWT with claims equivalent to the attributes produced by the `Authenticate` RPC.  Clients of authnd can then verify those JWTs via the `ExchangeTokenVerifier` and extract the same attribute bundle which they would have gotten from calling `Authenticate` on the originating access token.  To facilitate that, all public keys for current or recently used private signing keys are federating to clients via the `TOKEN_EXCHANGE_PUBLIC_KEYS`.

>[!IMPORTANT]
> The public keys in `TOKEN_EXCHANGE_PUBLIC_KEYS` are expected to be base64-encoded and `;`-separated, with the most recent keys appearing first.[^1]  

[^1]: This is an operational contract between the client and server which allows us to avoid serving a JWKS API from authnd.

### Rotating signing keys

In the event that the private signing key is leaked, we need to be able to rotate it without introducing downtime for our clients.  That procedure goes as follows (all steps completed on a prodshell host unless otherwise specified):

0. Set a STAMP in your environment, e.g.

```bash
export STAMP=prod-sdc-01
```

1. Generate a new signing key

```bash
openssl ecparam -name secp256r1 -genkey -noout -out $STAMP-te-signing-key.pem
```

2. Copy the signing key to the [shared authentication 1password Vault](https://github.1password.com/app#/gsa4rrwv77matapaonkxqnt54i/AllItems) with an appropriate name (e.g. `$STAMP-token-exchange-signing-key-$DATE`).

3. Generate the base64-encoded public key and add it to the existing keys. You may need to copy the private from 1password to the prodshell host first.

```bash
NEW_PUBLIC_KEY=$(openssl ec -in $STAMP-te-signing-key.pem  -pubout 2>/dev/null | base64 -w0)
OLD_PUBLIC_KEYS=$(vault-secret -a authnd -e $STAMP -k TOKEN_EXCHANGE_PUBLIC_KEYS)
vault-secret -a authnd -e $STAMP -k TOKEN_EXCHANGE_PUBLIC_KEYS -v "$NEW_PUBLIC_KEY;$OLD_PUBLIC_KEYS"
```


4. Deploy authnd to `$STAMP`[^3] to pick up the key and verify that the `authnd-tester` tests passed.

[^3]: `.deploy authnd/main to $STAMP` in the `#authnd-ops` channel in Slack.

5. Work with all dependent services federating `TOKEN_EXCHANGE_PUBLIC_KEYS` to ensure they get deployed. You can find an up-to-date list of services using the following chatop in `#authnd-ops` (or check [references in the secrets federation repo](https://github.com/github/secrets-federation/blob/415fb4e637007f208086b84c5ee4a8f1b47bfe11/config/federation/authnd/production/federate.yaml#L23-L36)):
```
.secrets-federation graph key=TOKEN_EXCHANGER_PUBLIC_KEYS app=authnd environment=production backend=vault
```

6. Validate that all dependent services have picked up the new public key using [this widget](https://app.datadoghq.com/s/59fe6c40c/mc3-h2m-muu).  We need to make sure all services have loaded the new public key.

7. Update the signing key for authnd in Vault, copying the private key from the Authentication 1password if necessary.

```bash
vault-secret -a authnd -e $STAMP -k TOKEN_EXCHANGER_SIGNING_KEYS --value-from-file $STAMP-te-signing-key.pem --newline-override
```

8. Deploy authnd to the affected stamps (via chatops in `#authnd-ops`):

```
.deploy authnd/main to $STAMP
```

9. Validate that clients stop using the old public keys using [this widget](https://app.datadoghq.com/s/59fe6c40c/ry7-qsa-v8g).

10. Remove all old public keys from Vault:

```bash
NEWEST_PUBLIC_KEY=$(vault-secret -a authnd -e $STAMP -k TOKEN_EXCHANGE_PUBLIC_KEYS | cut -d';' -f1)
vault-secret -a authnd -e $STAMP -k TOKEN_EXCHANGE_PUBLIC_KEYS -v "$NEWEST_PUBLIC_KEY"
```

11. Cleanup any secret files from the prodshell host:

```bash
rm *-te-signing-key.pem
```