# Spokes Access API Design Principles

## Make general purpose APIs

GitRPC has many APIs that are very specifically tailored to their call site.
We'd like to avoid this, and instead make general purpose APIs that make sense
for Git As A Service to offer, that are easy for future services to reuse, and
that are easy to iterate on as we grow.

## Type safety

Consider wrapping primitive types when the primitive type lacks important
semantic meaning. For example, OIDs are represented as `types.ObjectID`, a
wrapper around a string. File modes are represented as `types.Mode`, a wrapper
around a uint32.

### Abstractions

Repositories in Spokes are identified by a Type and ID.

### Structured

All structured data passed to or returned from Git must be parsed and passed as
a structure. Git typically represents structured data as a big string; Spokes
Access API does not.

### Pagination

All responses that include a variable amount of data should be paginated. When
a response is paginated, its request and response types define a cursor field.
A cursor is an opaque value that is only parsed by GitRPCd. If the response
includes a cursor, the client may request the next page of results by repeating
its original request and including the cursor. When the response's cursor field
is empty, there are no more pages.

### Selectors

Selectors are the way that Spokes Access API identifies the object or objects
that a request is going to look for and operate on. A selector in Spokes Access
API is similar to a treeish or commitish in Git.

Selectors should be type-safe. For example, if a request could look for a
commit by OID or by full ref name or by branch name, and the caller is expected
to be able to identify which it has, it should have a selector with three
`oneof` options, one for each. There are times when the caller doesn't know
what type of string it has; in these cases, use `types.Revision`.

### Avoid grab bag types

Grab bag types (e.g. sockstat) are very difficult to maintain. In particular,
it is almost impossible to be sure that it's safe to stop setting certain
values in a grab bag type. In Spokes Access API, add explicit fields for all
distinct values.

### Use HTTP headers sparingly

HTTP headers are a grab bag type and should be avoided for Spokes Access API
features. Do not use an HTTP header for required request data. Do not use an
HTTP header for information that would change the logical content of the
response.

## Errors

Return errors as twirp errors (rather than in the response body). See
[errors.md](errors.md).

## Prefer caching in Spokesd

Git data caches often use a repository's checksum as a part of a key so that we
can invalidate the cache when the repository is updated. However, this is an
implementation detail that we would like to encapsulate entirely within
Spokesd. We would also like to make caching work for all clients without every
client needing to add a Spokes-specific cache.

Prefer adding caching for endpoints in Spokesd. Add caching based on
demonstrated need for caching.

If caching needs to be client side, do not also add caching server side! And,
use the GetCacheKey to get the checksum. (We don't call it a checksum because
we want to be able to change which bit of data Spokes uses for this.)

## Feature flag in the monolith

This is more of a tactical, temporary thing. For now, Spokesd does not have an
efficient way to query feature flags that are set per-repository, but the
monolith does. While this remains true, add each feature flag that Spokes
Access API needs as a fields on `types.RequestContext` (for general-purpose
flags) or on the specific endpoint's request message (for endpoint-specific
flags).
