# Gitmon and Spokes API

Spokes API uses [Gitmon](https://github.com/github/gitmon) for rate
limiting. This document provides an overview of how Gitmon's quota
system works and discusses how it works for Spokes API.

## Gitmon quotas

Gitmon's rate limits are based on quotas and system health. When a fileserver
is "unhealthy" (too much CPU is active, too much memory in use, etc.), all
quotas get scaled down. In the most extreme case, an unhealthy fileserver's
quotas will be 1/20th as large as a healthy fileserver's quotas.

Quotas are defined for several different groupings of requests:
- Real IP
- Network ID
- Real IP + Repository ID
- User ID
- Spokes API Client ID

The primary way that Gitmon enforces quotas is by delaying requests. If there
are too many requests for a given quota, Gitmon will ask other related requests
to wait 7 seconds. It continues asking requests to wait until active requests
have finished. In cases of extremely bad server health, Gitmon will abort
requests instead of asking them to wait.

Gitmon also respects a request's Quality of Service (QoS). There are three QoS
options: no-delay, delayable, and fail-fast.

- No-delay means that Gitmon will still count a request against a quota bucket
  but never delay it. It's appropriate for frontend requests and update
  requests, where an artificial delay is not acceptable.  This is the default
  behaviour for monolith frontend requests.
- Delayable is the behaviour described above. It's appropriate for backend
  requests, and is the default behaviour for the monolith's background jobs.

  Note that the gitmon delay is included in the overall request timeout, so long
  running calls should account for that, and  set the `Request-Timeout` header to the longest time they're willing to wait. If gitmon needs to delay the request enough, the request will time out. 
- Fail-fast means that Gitmon will fail any request that exceeds a quota. It's
  appropriate in cases where the operation is optional or where the client
  would rather retry later than be delayed.

QoS is currently only used for Spokes API. For other requests, like cloning or
GitRPC, Gitmon uses request metadata to decide between "no-delay" and
"delayable" behavior.

See [gitmon docs](https://github.com/github/gitmon/tree/main/docs) for more
information about how Gitmon works.

## Spokes API

Spokes API clients provide input to Gitmon via the `RequestContext` field on
request objects. Gitmon's actions are reported in the response.

### Request Context

The request context includes information that Gitmon needs in order to apply
quotas correctly.

- `quality_of_service` (required) is the QoS.
- `user_id` (optional) is the ID of the user whose activity led to the current
  request.
- `real_ip` (optional) is the IP address of the client request that led to the
  current request.

### Response

Responses will include the total amount of Gitmon-induced delay as a header.
The value is in seconds. For example, if a request waited 14.1 seconds because
Gitmon requested it to delay, the response header would look like this:

    X-Gitmon-Delay: 14.1

If a response failed because Gitmon instructed it to fail, the HTTP response
code will be 429 and the body will contain a twirp error with the error code
[`twirp.ResourceExhausted`](https://pkg.go.dev/github.com/twitchtv/twirp#ErrorCode).
