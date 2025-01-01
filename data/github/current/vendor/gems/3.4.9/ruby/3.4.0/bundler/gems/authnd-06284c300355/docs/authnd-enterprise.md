# Authnd features in Enterprise environments

Currently, authnd only supports programmtic access token (PrAT) functionality for GHES. Other Enterprise environments (GHAE, Proxima) have no functionality support from authnd.

## Feature matrix

This table contains the public API methods of authnd, and their implementation levels in different versions of authnd.

| Feature | Dotcom production | GHES |
| ------- | ----------------- | ---- |
| Authenticator | * Authenticate(): <br> :green_circle: username + password <br> :green_circle: SSH public key <br> :green_circle: OAuth access token (legacy PAT) <br> :green_circle: signed auth token <br> :green_circle: programmatic access token | * Authenticate(): <br> :red_circle: username + password <br> :red_circle: SSH public key <br> :red_circle: OAuth access token (legacy PAT) <br> :red_circle: signed auth token <br> :green_circle: programmatic access token |
| CredentialManager | * IssueToken(): <br> :green_circle: programmatic access token | * IssueToken(): <br> :green_circle: programmatic access token |
|  | *VerifyCredentials(): <br> :green_circle: programmatic access token | *VerifyCredentials(): <br> :green_circle: programmatic access token |
|  | *RevokeCredentials(): <br> :green_circle: programmatic access token | *RevokeCredentials(): <br> :green_circle: programmatic access token |
|  | *FindCredentials(): <br> :green_circle: programmatic access token | *FindCredentials(): <br> :green_circle: programmatic access token |
| MobileDeviceManager | * RegisterDeviceKey() <br> :green_circle: | * RegisterDeviceKey() <br> :red_circle: |
|  | * RevokeDeviceKey() <br> :green_circle: | * RevokeDeviceKey() <br> :red_circle: |
|  | * RevokeDeviceKeys() <br> :green_circle: | * RevokeDeviceKeys() <br> :red_circle: |
|  | * FindDeviceKeyRegistrations() <br> :green_circle: | * FindDeviceKeyRegistrations() <br> :red_circle: |
|  | * FindDeviceKeyRegistration() <br> :green_circle: | * FindDeviceKeyRegistration() <br> :red_circle: |
|  | * RequestDeviceAuth() <br> :green_circle: | * RequestDeviceAuth() <br> :red_circle: |
|  | * GetDeviceAuthStatus() <br> :green_circle: | * GetDeviceAuthStatus() <br> :red_circle: |
|  | * FindActiveDeviceAuth() <br> :green_circle: | * FindActiveDeviceAuth() <br> :red_circle: |
|  | * CompleteDeviceAuth() <br> :green_circle: | * CompleteDeviceAuth() <br> :red_circle: |

## Service matrix

This table contains the various services/deployments that live in the authnd repository, and whether they run in different versions of authnd. For dotcom production, this is controlled via the presence of .yaml files in /config/kubernetes/default/deployments and in GHES, by the presence of a folder and .hcl.ctmpl files in the [enterprise2 repository](https://github.com/github/enterprise2/tree/master/vm_files/etc/consul-templates/etc/nomad-jobs).

| Service | Dotcom production | GHES |
| ------- | ----------------- | ---- |
| authnd | :green_circle: | :green_circle: |
| authnd-notifier | :green_circle: | :green_circle: |
| authnd-replicator-dead-letter-consumer | :green_circle: | :red_circle: |
| authnd-replicator-consumer | :green_circle: | :red_circle: |
| authnd-resyncer | :green_circle: | :red_circle: |

The authnd-producer is the [standalone service](https://github.com/github/authnd-producer) that handles ingesting changes of Dotcom production tables for replication, which authnd-replicator-dead-letter-consumer and authnd-replicatior-consumer read from. Thus, for consumers to be able to read in replication changes, an instance of authnd-producer must exist for the environment. Because it is standalone and deployed separately from other authnd services, it is not listed in the above table. For dotcom production, authnd-producer deployment is controlled via the presence of a .yaml file in its own repository's /config/kubernetes/default/deployments and in GHES, (would be) by the presence of a folder and .hcl.ctmpl file in the [enterprise2 repository](https://github.com/github/enterprise2/tree/master/vm_files/etc/consul-templates/etc/nomad-jobs). Because GHES uses a single database, replication is not necessary and authnd-producer is not deployed in GHES.

## General Enterprise design

Functionality within authnd is gated by stubbing the implementation of interfaces that are not relevant to Enterprise. Then, when running authnd, all code is compiled and based on configuration the server will inject either implemented or stubbed interfaces.
For dotcom production, all interfaces are implemented. For GHES, only Enterprise-relevant interfaces are implemented, and others are stubbed. This most notably applies to the injection of validators in the Authenticator ([example of non-functional interfaces](https://github.com/github/authnd/blob/main/internal/api/authenticator/authenticator.go#L92-L98)), and the retrieval of data from stores ([example of stubbing](https://github.com/github/authnd/blob/main/internal/common/store/mobile_auth_requests.go#L235).)

## Configuration

IS_ENTERPRISE_SERVER (modeled by CommonConfig.IsEnterpriseServer) is a boolean environmental variable that controls feature enablement within the authnd service (matching the Feature matrix above). This value is set in `/config/kubernetes/default/deployments` files for dotcom production, and in [nomad job](https://github.com/github/enterprise2/tree/master/vm_files/etc/consul-templates/etc/nomad-jobs) files for GHES. The functionality that this variable prevents for GHES is:

* disables the mobile device management API [ref](https://github.com/github/authnd/blob/d39399c4d4987f579e1a9eae8afc5b08c10f7c5b/internal/api/server.go#L191)
* prevents the instantiation of chatops endpoints (for triggering replication syncing) [ref](https://github.com/github/authnd/blob/d39399c4d4987f579e1a9eae8afc5b08c10f7c5b/internal/api/server.go#L191)
* instantiates an Authenticator with stubbed/unsupported authentication of non-programmatic access token credentials [ref](https://github.com/github/authnd/blob/16a0d38302d041ff025affb66d6fd228f6cb52e9/internal/api/authenticator/authenticator.go#L47)
* instantiates a data Store with stubbed/unsupported retrieval of data from tables that are not Enterprise-relevant (non-PrAT creds, mobile devices) [ref](https://github.com/github/authnd/blob/16a0d38302d041ff025affb66d6fd228f6cb52e9/internal/common/store/store.go#L55)
* configures server to use GHES database connection information [ref](https://github.com/github/authnd/blob/16a0d38302d041ff025affb66d6fd228f6cb52e9/internal/common/config/db.go#L191)

## Running in a codespace

You can use `script-server --enterprise` to run authnd with only Enterprise features, and without replication. This will set the `IS_ENTERPRISE_SERVER` environmental variable, and prevent starting up replication-related services.

You can hit most authnd endpoints [as usual](https://github.com/github/authnd/blob/main/docs/authnd-cli-client.md#connecting-to-the-service) except:

* mobile auth requests will return an error that the endpoint/function does not exist
* authentication of non-PrAT credentials will return an error about the function not being supported