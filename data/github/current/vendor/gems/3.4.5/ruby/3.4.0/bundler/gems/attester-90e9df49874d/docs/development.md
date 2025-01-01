# Local Development

When starting the server locally, the default configuration will use a static
signing key instead of connecting to an Azure Key Vault. The key and certificate
used can be found in the [certs/development](../certs/development) directory.

To re-generate the key and certificate, run the following command in the
`certs/development` directory:

```
openssl req -x509 \
  -newkey ec \
  -pkeyopt ec_paramgen_curve:prime256v1 \
  -days 3650 \
  -noenc \
  -extensions attester \
  -config cert.cnf \
  -subj "/O=GitHub, Inc./CN=Attester - development" \
  -addext "subjectAltName=URI:https://development-dotcom.releases.github.com" \
  -keyout private.key \
  -out leaf-attester.crt
```
