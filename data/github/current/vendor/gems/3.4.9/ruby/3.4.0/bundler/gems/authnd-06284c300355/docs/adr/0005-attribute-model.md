# 5. Attribute model

Date: 2020-09-29

## Status

Accepted

## Context

We need to define how Authnd will return data to callers in a way that is consistent with other GitHub
services and extensible.

## Decision

We will use an "Attribute" model, similar to what [authzd](https://github.com/github/authzd) accepts as input.
Authnd responses will consist of a set of key-value pairs using names of the form `[subject].[attribute]` such as
`actor.id` or `credential.type`.

## Consequences

By using this format, we can, in theory, pass authnd responses directly to authzd (which accepts a set of Attributes
as input to make authorization decisions). We also have the flexibility to add and remove Attributes without
breaking the Protocol Buffers schema.

This format does require that we maintain the "schema" of attributes since they are not expressed in the Protocol Buffers
schema. There is a risk that this schema might not stay in sync between callers. A caller may expect an attribute to
be of a different type than the server actually returns.
