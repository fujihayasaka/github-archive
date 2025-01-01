# Authnd Command Line Client

The `./cmd/authnd-client` package defines a command-line client that can be used to test authnd.

## Building

Build the client with `make cli`

## Running the client

Once built, the client will be present in `./bin/authnd-client`.
It has built-in help which can be accessed by running `./bin/authnd-client` with no arguments.

Provide credentials using the various options, and the client will either display the attributes returned along with their type:

```(bash)
user.id = [integer] 2
user.name = [string] "monalisa"
```

Or, in the event of an error, the error code:

```(bash)
Authentication failed: RESULT_FAILED_PUBLIC_KEY_NOT_FOUND
```

### Connecting to the service

By default, `authnd-client` will connect to a locally-running authnd instance using the development HMAC secret.
If you want to connect to another environment, use `--env` (or `-E`) to select an environment name (such as `production`) and the client will automatically set the address.
In addition, you can specify either the `--request-hmac` (or `-H`) option to provide a pre-generated HMAC (such as from the `.authnd hmac` chatop) or `--hmac-key` to specify the secret key used to generate an HMAC.
You can set `-k ~/.ssh/id_rsa.pub` to authenticate with a public_key.

**NOTE:** You must be connected to the [Production VPN](https://githubber.com/article/technology/production-vpn-access) to access the production authnd environment.

```(bash)
$ ./bin/authnd-client authenticate -E production -H <HMAC generated from running ".authnd hmac" in authnd-ops>
user.id = [integer] 2
user.name = [string] "monalisa"
```

### SSH Authentication

You can send SSH authentication information using `-k`:

```(bash)
$ ./bin/authnd-client authenticate -E production -H <HMAC generated from running ".authnd hmac" in authnd-ops> -v -k ~/.ssh/id_rsa.pub
user.id = [integer] 2
user.name = [string] "monalisa"
```

### Login/password Authentication

You can send login/password authentication information using `-l` and `-p`.
Both must be specified.
Beware of putting real credentials on the command line as they will be saved in your command history.
Use the `-P` option instead of `-p` and the client will prompt you to enter your password.

```(bash)
$ ./bin/authnd-client authenticate -E production -H <HMAC generated from running ".authnd hmac" in authnd-ops> -l <your github handle> -P
> Enter Password: <your password>
user.id = [integer] 2
user.name = [string] "monalisa"
```

### OAuth Token Authentication

You can send login/password authentication information using `-t`.
Again, beware of putting real credentials on the command line.
Use `-T` and the client will prompt you.

```(bash)
$ ./bin/authnd-client authenticate -E production -H <HMAC generated from running ".authnd hmac" in authnd-ops> -T
> Token: <some-token>
user.id = [integer] 2
user.name = [string] "monalisa"
```

### GitHub Mobile

You can register a mobile device and send auth requests to that device using our cli.

#### Register a Mobile Device

Generate a private key

```(bash)
$ script/gen-ecdsa-p256-keypair
> Private key saved to /workspaces/authnd/script/../dev/gh-mobile-dev.pem
```

Register your mobile device

```(bash)
$ ./bin/authnd-client mobile-device register-key  --user-id <User-Id> --oauth-access-id <Oauth-Access-Id> --device-model <Device-Model> --device-os <ios or android> --device-name <Device-Name> --private-key dev/gh-mobile-dev.pem
> Result: RESULT_SUCCESS
ID: 7
ExpiresAt: 2022-08-18 19:56:11.452894172 +0000 UTC
```

* Note: you will get a `duplicate fingerprint` error if you register another device with the same private key.

#### Send a Mobile Auth Request

Once you have registered a mobile device, you are now able to send active auth requests to approve or reject.

* Note: You have 1 minute from sending a auth request to completing it, otherwise the request will expire.

Create a request

```(bash)
$ ./bin/authnd-client mobile-auth request --user-id <User-Id>
> Result: RESULT_SUCCESS
Id: 1
Challenge: 23
Expires at: 2022-07-19 20:02:14.945321368 +0000 UTC
```

* Challenge does not always apply, you can skip the challenge by passing the `--skip-challenge` in

* The default type of request is `2fa_login`, if you want to have a different type of request, pass the `--type` flag in with one of these options (`device_verification`, `2fa_password_reset`, `2fa_sudo_challenge`)

Find the request

```(bash)
$ ./bin/authnd-client mobile-auth find --user-id <User-Id> --oauth-access-id <Oauth-Access-Id>
> Result: RESULT_SUCCESS
Request ID: 1
Payload: AAAAAGLXDYqXuXxndh3nh8rZBnPVKTQv9FICPOwdCP5HkbyL53mABg==
ChallengeRequired: true
HasValidDeviceKey: false
RequestType: 2fa_login
```

Complete the request

```(bash)
$ ./bin/authnd-client mobile-auth complete --approve --auth-request-id <Auth-Request-Id> --payload <Payload> --private-key dev/gh-mobile-dev.pem --user-id <User-Id> --oauth-access-id <Oauth-Access-Id> --challenge <Challenge-Number>
> Result: RESULT_SUCCESS
```

* If you want to reject the auth request, replace `--approve` with `--reject`
* If you passed in `--skip-challenge` when creating the flag, you will not need the `--challenge` flag when completing the request

### Issue/Revoke PRaT (PATv2) Tokens
To issue a token, the following arguments are required: `actor.type`, `actor.id`, `access.id`, and `-t programmatic_access_token`.
* You can specify non-default attributes such as `my.thing:string=foo`

```bash
./bin/authnd-client issue  actor.type=User actor.id=1 access.id=5 -t programmatic_access_token
Token: github_pat_11AAAAAAI...yzcT5vAZ
Token ID: 4
```

Revocation of a token can be done two different ways: by Id or by token.

To revoke by Id, include the token Id at the end of the command.
```bash
./bin/authnd-client revoke --reason "testing" --type "programmatic_access_token" 4
Revoke Result: RESULT_SUCCESS.  (4)
```

To revoke by the token itself, replace `--type` with `--token` and omit the Id from the command.
```bash
./bin/authnd-client revoke --reason "testing" --token github_pat_11AAAAAAI...RdBLNVT2
Revoke Result: RESULT_SUCCESS.  (RdBLNVT2)
```

### Run against local service

If you want to use the authentication client on the local service leave `--environment` (`-E`) and `--hmac-key` (`-H`) out of the command and they will default to local values.

For example, signing in with a password would look like this:

```(bash)
$ ./bin/authnd-client authenticate -l monalisa -P 
> Enter Password: passworD1
actor.type = [string] "user"
user.login = [string] "monalisa"
```
