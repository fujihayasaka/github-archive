proto/entities
==============

The Protobuf files in this directory represent data structures that are passed around the
monolith, such as Repositories, Pull Requests, and Commits.

They are heavily inspired by (and in some cases directly copied from) the protobufs found
in [github/hydro-schemas](https://github.com/github/hydro-schemas/tree/main/proto/hydro/schemas/github/v1/entities).

If you are changing or adding a schema, take care to stick to established conventions for field
names based on the upstream entity or model, if possible.
