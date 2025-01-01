# Common Spokes Access API Errors

This document describes errors that Spokes Access API returns, along with more
information about why the errors occur and how client apps should respond to
the errors.

## `twirp.InvalidArgument` (400)

This error indicates that a request didn't include the necessary data. This is
usually a bug in the client because the request is missing required fields.

## `twirp.Unauthenticated` (401)

This error indicates that Spokes Access API could not determine the client's
identity. This error can only occur in the Request-HMAC-authenticated
deployment in production. If authentication were to fail with the
Client-cert-authenticated deployment, the error would be a TLS protocol error
in the client.

## `twirp.NotFound` (404)

This error can occur in a few situations.

- Repository is not found in spokesdb. This typically happens if a repository
  is deleted in between user activity and a subsequent Spokes Access API
  request. This can also happen if the wrong repository type is used (e.g.
  "repository" with a Gist's ID).
- Repository does not exist on disk. This typically happens if a repository is
  deleted in between user activity and a subsequent Spokes Access API request.
- A requested object or reference was not found in the repository. This can
  happen if the request names a reference that is deleted by a user. This can
  also happen if the object is not referenced and a GitHub employee performs a
  pristine GC on the repository. Occasionally, this will happen during or
  immediately after a push that is adding the requested object to the
  repository.

In general, these requests should not be retried.

## `twirp.DeadlineExceeded` (408)

This error indicates that the request took too long to process. Generally,
requests like this will never complete in the allowed time. Clients should
adjust their queries so that they request less data at a time.

## `twirp.ResourceExhausted` (429)

This error can occur in a few situations.

- Gitmon indicated the request should 'fail'. This will typically only happen
  when the request's QOS is "fail-fast" and the request exceeds a quota.
- The request exceeded a memory limit. The error message will include "memory
  limit exceeded".

It is OK to retry (after a delay of at least 15s) when the error is from
Gitmon. Do not retry when the error message includes "memory limit exceeded".

## `twirp.Internal` (500)

This is the least specific error that Spokes Access API might return.
- Spokesd encountered an error retrieving data from mysql.
- Spokesd encountered an error retrieving a Gist's name from the monolith's
  internal API.
- `GetBlobContents` will return this if the request is for a valid OID that is
  not a `blob`. (Note: this should be a 4xx.)
- A repository is corrupt.
- Other errors, including unrecognized errors from `git`.

It's OK to retry these, preferably with exponential backoff. If the error
persists for more than one business day, please contact Git Systems so that we
can investigate the problem.
