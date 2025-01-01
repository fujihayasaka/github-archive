# 29. PATv2 schema

Date: 2021-08-03

## Status

Accepted

## Context

This is the next iteration for token management in Mint. The goal of PATv2 (Personal Access Token version 2), which is being developed by the Apps team, is to provide a more flexible and extensible token management system that gives more granularity to users and organizations.  The goal of this document is to describe the schema necessary for supporting delivery of PATv2.

Beyond issuing, revoking, and authenticating tokens, which have been discussed at length in the project Mint [design doc](https://docs.google.com/document/d/1ymcNOfG2HuTPckRGDgzowXhbE8cCSOiKCwWdBYfEmuw), the Apps team needs these tokens to be queriable via `authnd`.  The two ways that the Apps team intends to query existing Mint PATv2 tokens are:
1. By actor (`actor.id == 1234 AND actor.type == user`)
2. By access (`actor.id == 1234 AND actor.type == user AND access.id == 5678`)

The `actor.id` and `actor.type` above are token attributes that are already present in our existing
[`mint_v0_tokens`](https://github.com/github/authnd/blob/a7efd25832c04e0379028d0687f5f6ae17f9818d/schemas/authnd/mint_v0_tokens.sql#L1-L14) schema.  The meaning and purpose of the `access.id` attribute are discussed below.

## Decision

We will introduce a new table and token type to support PATv2 in project Mint. The new table's schema will be based upon the existing `mint_v0_tokens` table with a few additions. The V0 table and token type will continue to exist independently.

The new schema is as follows:

```(sql)
CREATE TABLE user_programmatic_access_tokens (
    `id`             bigint unsigned     NOT NULL AUTO_INCREMENT,
    `hashed_token`   varbinary(64)       NOT NULL,
    `token_suffix`   varbinary(8)        NOT NULL,
    `actor_id`       bigint unsigned     NOT NULL,
    `actor_type`     nvarchar(40)        NOT NULL,
    `access_id`      bigint unsigned     NOT NULL,
    `issued_at_utc`  datetime            NOT NULL,
    `expires_at_utc` datetime            NULL,
    `revoked_at_utc` datetime            NULL,
    `attributes`     blob                NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `index_user_programmatic_access_tokens_on_hashed_token` (`hashed_token`),
    KEY `index_user_programmatic_access_tokens_on_actor_type_and_id` (`actor_type`, `actor_id`)
    KEY `index_user_programmatic_access_tokens_on_actor_type_and_id_and_access_id` (`actor_type`, `actor_id`, `access_id`)
)
```

The key changes are the introduction of the required `access_id` column and corresponding index.  This column corresponds to the primary key of the `user_programmatic_accesses` table in the [Apps PATv2 DB design](https://docs.google.com/document/d/1x3kayFB0Y52eF4MbOPMOX3W-BSn0B-qir1JWXZmEJlY/edit#heading=h.z1t4ea8q0hzi); _note, the linked diagram uses an outdated name for the table, `user_api_accesses`_. Each Mint PATv2 token will correspond to exactly one `UserProgrammaticAccess`. The converse is also true today, though the relationship may become one-to-many when server-to-server tokens are introduced at a later date.  All other tables in the App database design are outside of the scope of Authentication.

Notably, the expiration remains optional as in the V0 token schema.

## Consequences

Since PATs need to be looked up by `access_id`, introducing an index on `actor_type`, `actor_id` and `access_id` allows us to perform that lookup quickly. Incorporating the `actor_type` and `actor_id` into the query also allows us to ensure we can perform the query on a single shard if/when we shard tokens by actor identity.

PATv2s are granted access _after_ they are provisioned, which is a change from PATv1. Moreover, the access grants can be subject to business/organization admin approval. As a result, the token can be in a state where it's created but has no permissions. However, this should not affect the validity of the token from the Authentication perspective and results in no change to the schema or handling.

## Helpful links

- [MINT EDR](https://docs.google.com/document/d/1ymcNOfG2HuTPckRGDgzowXhbE8cCSOiKCwWdBYfEmuw/edit#heading=h.p7fafm28bw5)
- [PATv2 EDR](https://docs.google.com/document/d/1x3kayFB0Y52eF4MbOPMOX3W-BSn0B-qir1JWXZmEJlY)
- [Token management ADR](../0026-develop-a-new-token-management-api.md)
- [PATv2 schema meeting notes](https://docs.google.com/document/d/1z_dfY0S5xkNKuIWBmMVpNX_f0ciePgoDuWieAcr66bo)
