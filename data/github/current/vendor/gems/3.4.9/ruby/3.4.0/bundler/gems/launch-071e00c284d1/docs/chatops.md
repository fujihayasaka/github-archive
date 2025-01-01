# How to add a chatops command to Launch

These are the steps needed for adding a ChatOps command to the launch app. 

## Setup the Launch app working locally

Follow the steps in [local dev](./local-dev.md) to get Launch running locally.

## Add command regex to existing chatops file

Update the code in [`chatops/chatops.go`](/chatops/chatops.go) to provide information about what regex chatops will look for when a user types in `.launch`.
For example, the following addition would run the `chatopsTenant` function whenever a user typed `.launch az-nwo thomabr/test`

```go
{
  Name:    "az-nwo",
  Help:    "az-nwo Provides details about az resources by NWO",
  Regexp:  `az-nwo (?<nwo>[^\s]+)\s*(?<env>[^\s]*)`,
  Handler: app.chatopsTenant
},
```

## Add protocol buffer interfaces for your RPC service.

Update [`proto/services/deploy.proto`](/proto/services/deploy.proto). You should add a function that your handler will call that takes in a request, and returns a response.

Run `script/protoc` everytime you change this 

See [Protocol Buffers](https://developers.google.com/protocol-buffers/docs/gotutorial) for some documentation.

## Add a handler to parse out the parameters from chatops and call the appropriate functions

Add a new file similiar to `chatops/chatops_{mychatopscommand}.go`. This file is referenced in the Handler of the chatops property above.
This function takes in a `Command` request from the chatops command, parses the parameters, runs your query, then outputs the results.
This function should match the RPC protocal buffer interface you defined above.

## Add your logic to the the appropriate service

Add your logic that calls some other API in order to return the appropriate information

## (Optional) Protect the chatops with RBAC and 2FA

First determine if you need this.
RBAC and 2FA are intended to protect high risk chatops.
The criteria for that is listed at https://thehub.github.com/security/policy-desk/standards/chatops-command-security-and-risk-standard/?reloaded=true#high-risk-chatops.
If your chatops meets that definition, then you need to take a couple of extra steps.

First, wrap the chatops handler with the middleware that prompts the user for security checks.

Before:

```go
{
  Name:    "az-nwo",
  Help:    "az-nwo Provides details about az resources by NWO",
  Regexp:  `az-nwo (?<nwo>[^\s]+)\s*(?<env>[^\s]*)`,
  Handler: app.chatopsTenant,
},
```

After:

```go
{
  Name:    "az-nwo",
  Help:    "az-nwo Provides details about az resources by NWO",
  Regexp:  `az-nwo (?<nwo>[^\s]+)\s*(?<env>[^\s]*)`,
  Handler: security.WrapWithAuthorization(app.validator, app.prompter, app.chatopsTenant),
},
```

You should also mark the risk level of your chatops in the Hubot config.
That config is at https://github.com/github/hubot-rpc-config/blob/6605edd7f8e07ce399a0221e2c799e3caece4407/rpc-endpoints/launch.yaml

### Background on Setup

This section describes one time setup for RBAC and 2FA in our chatops.
You can skip this section unless you need to repeat the process for a new Proxima stamp.

As a pre-requisite, Launch needs some credentials for Chatterbox and LDAP.

LDAP access can be granted by the security-iam team.
e.g. https://github.com/github/security-iam/issues/9116
Someone from that team will provide secrets needed into the requested Vaults.

Chatterbox secrets are provided through secrets-federation.
An example for the production environment Vault is https://github.com/github/secrets-federation/pull/884.
You can file a PR for other stamps or environments as needed.

With secrets in our Vault, you can now reference them in the k8s manifests.
Here's an example:

```
  - name: CHATTERBOX_TOKEN
    valueFrom:
      secretKeyRef:
          name: launch-production
          key: chatterbox-token
  - name: LDAP_BINDPW
    valueFrom:
      secretKeyRef:
          name: launch-production
          key: ldap-bindpw
```

The last piece of configuration is the LDAP and 2FA configuration.
These configurations tell the middleware which groups have access to the chatops, which Slack channels they can be run from, and which endpoint the LDAP service is at.
The current files that provide these details are in these locations:

- [config/security/ldap-config.yaml](./config/security/ldap-config.yaml)
- [config/security/security-config.yaml](./config/security/security-config.yaml)

These are then copied into the Docker container image so they can be read when launch-chatops starts up.

```
COPY --chown=github:github --from=builder /go/src/github.com/github/launch/config/security /etc/launch-chatops/security
```

## Testing chatops in Lab

Use the `@lab` suffix to verify the new chatop command in the Lab environment
```
.help launch@lab
.launch@lab <command>
```

## Testing chatops locally

### Testing the code from launch
You can test chatops locally or with `bp-dev`.

Once you have all services running (using aqueduct), you will need to call `http://127.0.0.1:5003/_chatops` endpoint to `POST` chatops commands. 

Example:
```
curl --request POST 'http://127.0.0.1:5003/_chatops' --header 'Content-Typeon/json' --data-raw '{"user":"user","method":"az","params":{"repo": "github/hub", "env":"development"},"room_id":"test"}'
```

Result:
```
{"result":":msft: Azure details for github/hub in development (https://github.com/github/hub):
*Repo - GlobalID* MDEwOlJlcG9zaXRvcnkx
*Repo - DatabaseID* 1
...
"}
```

Note: if you face `Missing signature header`, there is a way to add this signature as an header `Signature keyid=%s,signature=%s`
(see [here](https://github.com/github/hubot-classic/blob/0d7960d0885db5988ad2c52e37be96037ca1ebeb/docs/rpc_chatops_protocol.md#authentication) for more information on auth).

### Testing end to end

Clone `hubot-classic` [repository](https://github.com/github/hubot-classic) :

```
git clone git@github.com:github/hubot-classic.git
```

Then after bootstrapping `script/bootstrap` the project, rename `config/chatops-rpc/development.yaml.example` to `config/chatops-rpc/development.yaml`

You need to add your endpoint to test, for example:
```
# ChatOps RPC endpoints for development
template:

endpoints:
  - prefix: launch@dev
    url: http://127.0.0.1:5003/_chatops
    owner: your_handle
    methods:
      az:
        risk: low
```

Start hubot with `DUO_ENABLED=false script/server` and run `.help`. You should see your command in the list.

Now you can call your command as `.launch@dev az github/hub`, you should get the same result as above from hubot this time.
