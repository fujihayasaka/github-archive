# 8. Credential Replication Security

Date: 2020-10-20

## Status

Superceded by [18. Use Maxwell to replicate data to authnd](0018-use-maxwell-to-replicate-data-to-authnd.md)

## Context

In order to break out and scale authentication independently from the monolith,
as a first step we will be replicating credentials from dotcom to the new authnd database.
(see [ADR #6](0006-replicating-credential-data.md))
That database will eventually be used by the authnd service for authenticating users.

We will be migrating data from the dotcom database to an authnd database in multiple steps.
Initially, any time a credential is updated/deleted, we will be saving that to the authnd database.
Once that's in place we will backfill the remaining credentials. 

In order to save the modified/deleted credentials to the authnd database
we will use hydro to publish messages that will be consumed by the authnd replicator service.
These hydro messages need to be encrypted to ensure that an unapproved consumer does not intercept the message and compromise sensitive credential data within the message.
This ADR will focus on securing data within hydro messages.
The backfill step will be addressed in a future ADR.

## Decision

We have decided to go with Option 2: Shared Secret + NaCl. Potential Earthsmoke retirement is the major
driving factor here. Also, its rolling of keys doesn't quite provide the expected level of security
we were expecting, as a compromised Earthsmoke client token would compromise all historic encrypted
message payloads.

## Option 1: Earthsmoke

### UPDATE (11/4/2020): We learned that more likely than not, Earthsmoke may soon be retired.

Encrypting all hydro messages that are produced by dotcom that are consumed by authnd and contain 
sensitive credential data with Earthsmoke.
The authnd replicator will decrypt the message payload.
We will also be rotating these encryption keys daily (schedule to be confirmed with appsec).

GitHub has a paved path for this with [earthsmoke](https://github.com/github/earthsmoke),
which manages the encryption keys that will be used by both the producer and consumer of our hydro messages.
There is a ruby client library for dotcom as well as a golang client library for authnd.
This client library provides methods for encrypting, decrypting, signing, verifying signatures, rolling/rotating keys.

#### Overview:
Dotcom
- keeps latest encryption key in memory
- performs encryption locally
- every 24 hours: sends a request to earthsmoke to rotate the key
- keeps a 6 hour cache of the latest version of the earthsmoke encryption key

Authnd
- performs decryption via the earthsmoke golang client which communicates with the earthsmoke service to decrypt the message.

### Earthsmoke Concerns
- Earthsmoke services currently serve up about 300 requests/sec.
Prodsec raised concern about request rate if we did not handle encryption/decryption locally.
After analysis of current throughput for inserts/deletes for public ssh keys which is about 0.03/sec,
we are comfortable decrypting via the earthsmoke service and encrypting the hydro messages locally.
As we start replicating the other credential types and this rate increases such that earthsmoke can't handle it,
we will need to look at decrypting locally.
- As of the time of this writing, the Golang earthsmoke library is lacking the local functionality that is provided by the Ruby client,
and only encrypts/decrypts by issuing requests to the earthsmoke service.
This doesn't affect the hydro message producer (encryption) side, but rather the consumer (decryption).
Any change to our consumer to decrypt messages locally will require us to implement that in the golang earthsmoke client. 

Dotcom will manage the creation and rotation of the key.
Dotcom will need to store the latest version of the key locally in memory so we don't spam the earthsmoke service or introduce lag in existing dotcom workflows.
As a credential is modified, dotcom will locally encrypt the sensitive information and include that in an encrypted payload property of the hydro message.
(NOTE: We will need to modify the existing hydro message schema for ssh public keys to support this new property).
Dotcom will pass the encrypted credentials as well as the version of the encryption key that was used.

On the consumer side, the authnd replicator service will make a request using the earthsmoke golang client to decrypt the message.
It will need to pass the version of the key that was used to encrypt it, which will be included unencrypted in the message body.

## Consequences

- Encryption keys will be kept in memory in dotcom
- A compromised encryption key would provide access to 24 hours worth of data.
- A compromised client token would provide access to ALL historic encrypted message payloads because
the client token is required to communicate with Earthsmoke and the message includes the plaintext
version of the encryption key that was used to encrypt the message. Thus an attacker could just
make the request to Earthsmoke using the token, key, and the key version to decrypt the payload.

#### Note:
At the beginning of this replication feature we will only be working with ssh public keys.
The authnd service will be running in production behind a feature flag and science experiment,
and will not make any actual authentication decisions.
Because we're sending public data and not using it for anything,
we might begin the replication work before landing on an encryption strategy,
and will drop the database after we've added the necessary encryption protections in the future.


## Option 2: Shared Secret + NaCl

### Overview:
- Both Dotcom and Authnd will share a secret in their respective vaults, which will be used to
initialize [NaCl libraries](https://nacl.cr.yp.to/) to encrypt/decrypt Hydro message payloads.
- To support rolling the shared secret, the authnd vault will have a primary and secondary value on which
we will rotate when updating the key. Rolling the shared secret will initially be done manually when it's deemed
necessary, but this is something we can improve upon in a future feature.
- Encryption/Decryption will all occur locally, in memory for each service using the respective
[Ruby](https://github.com/RubyCrypto/rbnacl) and
[Golang](https://godoc.org/golang.org/x/crypto/nacl/secretbox)
NaCl libraries.

## Consequences

- If Earthsmoke is indeed retired in the future, we don't have to come up with an alternate solution.
- Earthsmoke service availability is no longer a concern for the message consumer (Authnd).
- Requires manual rolling of encryption key secrets if the key is compromised.
- A compromised dotcom/authnd secret would provide access to all encrypted message payloads
encrypted with that secret encryption key until it is rolled to mitigate the breach.
