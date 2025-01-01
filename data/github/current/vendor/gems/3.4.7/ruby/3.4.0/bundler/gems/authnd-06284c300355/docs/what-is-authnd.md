# What is Authnd?

Authnd is an "Authentication Service" for GitHub.
More practically, it's an RPC (Remote Procedure Call) service that accepts requests from other GitHub services to resolve *Credentials* into a set of *Attributes* describing the user and the access granted by that credential.

Authnd is generally spelled as a single word, so "Authnd" at the start of a sentence, and "authnd" mid-sentence. The `d` is not capitalized. It is pronounced: auth-en-dee.

## Authentication vs Authorization

It's good to make sure we're all on the same page regarding terms:

* **Authentication** is the process of identifying *who* a user is, by validating credentials. Authentication processes provide metadata describing the user and their access level.
* **Authorization** is the process of identifying if a user can access a specific resource. Authorization processes take metadata about the user and their access level as input, as well as metadata describing the resource the user is attempting to access and return an `ALLOW` or `DENY` response.

Authnd is only responsible for **Authentication**.
Authorization at GitHub is handled within the various services, often by using a related service: [authzd](https://github.com/github/authzd/).

## Helpful Terms

### Actors

An *Actor* is the entity making the request. Most commonly, this is a "user" (generally a human being, but sometimes an automated account of some kind).
Other kinds of actors include:

* GitHub Apps
* GitHub App *Installations* / Bots
* OAuth Apps (NOTE: this is not the same as a user acting *through* an app, this is the app itself)
* Repositories (see [Deploy Keys](https://docs.github.com/en/free-pro-team@latest/developers/overview/managing-deploy-keys#deploy-keys)

### Credentials

Authnd takes *Credentials* as input.
Credentials are any data that a user presents to authenticate themselves.
Below are some example *Credentials* (the list is **not** exhaustive!):

* An SSH Public Key (assuming the *caller* has proven the user has access to the private key).
* A Personal Access Token or OAuth Token.
* A username, password and optionally, two-factor code.
* A browser session cookie.
* An internally-issued token, such as a Signed Auth Token.

NOTE: For SSH keys it's important to note that authnd does not perform any SSH handshaking to validate that the user actually has the private key!
It's up to callers to perform that validation before passing the key along to authnd.
Public keys are just that, public, and cannot serve as credentials unless you have proven that the user holds the matching private key.

### Attributes

Authnd responses contain a set of *Attributes* describing the actor and the credential they presented.
See [Attribute Schema](attribute-schema.md) for up-to-date information on common attribute names and expected values.

## How clients use authnd

Authnd provides a [Twirp](https://github.com/twitchtv/twirp) service defined by a [Protobuf spec](https://github.com/github/authnd/blob/main/proto/authentication/v0/authentication_api.proto).
Clients make Twirp requests to the `Authenticate` API, providing the credentials they wish to validate.
Authnd processes those credentials and produces a set of **Attributes**, which are key-value pairs.
The keys are string names of the form `[subject].[attribute_name]` where `[subject]` is the subject being described by the attribute and `[attribute_name]` is the specific attribute itself.
The values are any of [a variety of data types](https://github.com/github/authnd/blob/main/proto/authentication/v0/attributes.proto).

Once a client has authenticated a credential, it uses the attributes returned to determine if the actor has access to the resource they are attempting to access.
We recommend using our partner service [authzd](https://github.com/github/authzd/) to do this.
Authzd takes a set of attributes describing an actor **and** the resource they are trying to access and returns and authorization decision.
Since authzd is a relatively new service, many clients also use custom code for authorization.

There are currently two supported "clients":

* The [`authnd-client`](../cmd/authnd-client/) command-line client.
* The [`authnd-client`](../ruby) Ruby gem.

Consumers working in Go can use the generated Twirp client in the [github.com/github/authnd/api](../api) until a formal client is defined.

## How authnd resolves credentials

Once you dive through all the Twirp boilerplate, you end up at the [`internal/authnd/authenticator/validators`](../internal/authnd/authenticator/validators) package,
which provides a set of "Validators" that take credentials and produce a set of Attributes.
Currently, these connect directly to the dotcom MySQL databases and perform lookups in the various tables that store the credentials and validate them.

Moving forward, we are planning on a [Data Replication](adr/0006-replicating-credential-data.md) process to replicate data from dotcom's databases to a new database specific to authnd in order to take pressure off the dotcom MySQL databases.
This will also prepare a path for when authnd *owns* credential data.
