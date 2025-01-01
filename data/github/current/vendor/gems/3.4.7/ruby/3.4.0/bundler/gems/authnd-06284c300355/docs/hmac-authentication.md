# HMAC-based Authentication

To communicate with authnd, you need to include a token signed by a shared key.
This includes local development, though the key is not secret.

## Generating an HMAC

If you have the secret shared key, you can generate an HMAC value using the `./script/gen-hmac` script in this repo:

```shell
> ./script/gen-hmac super-secret-key
123456.0abc...
```

Running `gen-hmac` with no arguments will generate a token the default development secret.

Use the token value in the 'Request-HMAC' header in your requests, like so:

```shell
$ curl -H "Request-HMAC: $(./script/gen-hmac)" ...
```
