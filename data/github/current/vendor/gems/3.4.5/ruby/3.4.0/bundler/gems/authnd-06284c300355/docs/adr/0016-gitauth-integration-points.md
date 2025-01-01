# 16. GitAuth Integration Points

Date: 2020-08-06

*NOTE: This was a non-ADR design doc from the Wall-E experiment that has been absorbed in as an ADR. It's number does not represent the actual order in which it was created, and it's format differs from the others.*

## Status

Accepted

## Context

This document investigates the options for integration points within the GitAuth domain of the Monolith.
This particular region of the Monolith contains several branches of logic that could be useful for driving out the functionality we’ll need to support as we begin understanding the impact of rolling out a new Authentication mechanism,
side-by-side with our battle tested codepaths.

### Goals

* Layout project context, assumptions
* Understand the state of GitAuth as it pertains to Data, logic in the Monolith today
* Layout the complexities that exist today in the various branches of GitAuth Authentication

### Non-Goals

* Assert options to begin integrating the new Authentication service with the GitAuth in the Monolith
* Outline how to carve Authentication out of the Monolith

## Background

Before we dive into the topic at hand, let’s lay out a framework for how this document lays out integration and the reasoning behind it.

An Authentication (Authn) service is being developed.
As part of that work, we'll begin integrating with the monolith such that we can begin to understand that we indeed can integrate with important code paths in the Monolith,
and that we understand the performance and operational impact this has on various instances of GitHub.

This Authn service will require access to data that is traditionally owned by the monolith.
As such, an important piece of the Authn work is to begin to understand what logical, data boundaries should exist as an Authn service begins to materialize and take over portions of the code owned by the monolith today.
The way this document approaches that conversation is to:

* Investigate the various branches of code within GitAuth today
* Understand what database tables are needed to answer various Authn questions

## GitAuth

Git requests are proxied through a service called [`babled`](https://github.com/github/babeld).
`babeld` is the service in front of git requests that’s responsible for making a precursory check on whether a request is authenticated, then that’s authorized.

`babeld`, being the front-door proxy for git, will:

1. Accept a git request
1. Take request data and forward that to the GitAuth service (which lives in the Monolith) to request auth information
1. Using that information it will decide whether and how to forward the request into internal git services

With the high-level dependencies in mind from this section, let’s dig into some of the complexities within the Monolith.

Ruby has a library and concept called [`Rack`](https://github.com/rack/rack).
Rack fulfills and defines a basic webserver interface such that a variety of webservers can accept and serve traffic to an instance of it.
It’s a relatively simple concept that allows you to "mount" middleware that add or react to various properties of a request or response.
Middleware that actually handle, and respond to a request are generally referred to as Rack Apps.
Rails itself is a Rack App.
Since you can mount many Middleware and therefore Apps onto a single Rack "stack,"
this means you can implement your own very specific request handlers that technically live outside the Rails request lifecycle,
but the code is loaded in the same way, giving you access to things like your project Models, library code, configuration.
With this background, you could load a webserver with a stack like this:

1. `Middleware::Logging`
1. `Middleware::ErrorHandling`
1. `Middleware::Context`
1. `SomeRailsApp`

What generally happens in practice - especially in production - is that there’s a [stack configuration](https://github.com/github/github/blob/faaf91f13faffacf3eb304af29256570a7ec2372/config.ru) for the main Rails app,
then there’s [a stack](https://github.com/github/github/blob/faaf91f13faffacf3eb304af29256570a7ec2372/gitauth.ru) for GitAuth.
This means we effectively boot the two as separate binaries, but they run a lot of the same internal code.
For instance, GitAuth accesses the User model extensively, which is booted with all the same configuration and code that the main Rails app has.
Recall that with `babeld` we access GitAuth for basic Authn and Authz concerns, which effectively has access to the entirety of the Monolith technically - though not used that extensively in practice.

Within the Monolith there are several branches of logic for handling GitAuth that handle specific Authn scenarios.
Those scenarios are: `verify-key`, `verification-token`, `git-lfs-authenticate`, and default - default will handle the generic "can actor perform action on resource."
Let’s breakdown the high-level logic, but more importantly the data connections of each scenario in more detail.

[`verify-key`](https://github.com/github/github/blob/aca0554faf4bbec2e5adf2447df386f1d1345c52/lib/github/repo_permissions.rb#L346-L353) identifies an SSH key and maps it to an actor.
This is an initial step that’s required to enable an SSH key to be used in any of the subsequent scenarios.
This path actually splits into two major sub-paths: `verify-cert` and `verify-public-key`.
For `verify-cert` after parsing incoming data we wind up querying tables `users`, `ssh_certificate_authorities`, and `business_organization_memberships` multiple times.
For `verify-public-key` we use the parsed request data to select against tables `public_keys` and `users` tables multiple times.

[`verification-token`](https://github.com/github/github/blob/aca0554faf4bbec2e5adf2447df386f1d1345c52/lib/github/repo_permissions.rb#L355-L374) is used when a user runs `ssh git@github.com verify` which generates a token that can be sent to support to unlock an account that’s lost 2FA access.
For this code path, we extract some data with which to query `users` and `public_keys` then use this to generate an HMACtoken.

[`git-lfs-authenticate`](https://github.com/github/github/blob/aca0554faf4bbec2e5adf2447df386f1d1345c52/lib/github/repo_permissions.rb#L376-L394) generates a token specifically for GitLFS access.
The resulting token is passed as an Authentication header via HTTPS requests.
This code-path extracts command metadata, then passes into internal tooling to process the request - I will describe the rest of this in "default scenario" below, because the rest of the functionality more or less overlaps with this code path.

The [default scenario](https://github.com/github/github/blob/aca0554faf4bbec2e5adf2447df386f1d1345c52/lib/github/repo_permissions.rb#L396-L439) is used for anything else - think `git pull`, `git push` or other git remote access.
This code-path does some specific checks for things like "maintenance mode," GHES/GHPI license details which appear to come from how the instance was booted.
Parsed request data results in query across the tables `users`, `ssh_certificate_authorities`, `business_organization_memberships`, `public_keys`, `oauth_accesses`, `authentication_tokens`, `compromised_passwords`, `authenticated_devices`, `scoped_integration_installations`, `integration_installations`, `integrations`, `repository_accesses`, `kv` (a general key-value table implemented with [github-ds](https://github.com/github/github-ds)) each up to several times.
`organization_credential_authorizations` is called in an authorization step, though we may need to call this to enumerate organizations a token has access to as part authn work.
This path also results in an update to `public_keys`, `oauth_authorizations` and stores an auth attempt in certain circumstances.
It should be noted that this code path is written mostly as a pipeline, meaning this flow can be split more deeply if it would serve our needs.
Specifically, it’s split into `Anonymous`, `Slumlord`, `SignedToken`, `SSHCertificate`, `SSHKey`, `TempCloneToken`, and `RequestCredentials.`
SSHCertificate and SSHKey flows have some functional and conceptual overlap with the code-branches in `verify-key`.

### Table breakdown

* `verify-key`
  * `verify-cert`
    * read
      * `users`
      * `ssh_certificate_authorities`
      * `business_organization_memberships`
  * `verify-public-key`
    * read
      * `public_keys`
      * `users`
* `verification-token`
  * read
    * `users`
    * `public_keys`
* `git-lfs-authenticate`
  * read
    * `users`
    * `ssh_certificate_authorities`
    * `business_organization_memberships`
    * `public_keys`
    * `oauth_accesses`
    * `authentication_tokens`
    * `compromised_passwords`
    * `authenticated_devices`
    * `scoped_integration_installations`
    * `integration_installations`
    * `integrations`
    * `repository_accesses`
    * `kv`
    * `organization_credential_authorizations`
      * Called during authorization, but we need to return organizations authorized by a given token
      * https://github.com/github/authnd/issues/24#issuecomment-668363339
  * write
    * `public_keys`
    * `oauth_authorizations`
* default
  * same as `git-lfs-authenticate`

## Disclaimer

It should be assumed that it's possible this list of data access points and high-level logic is flawed or incomplete.
When replacing these pieces of functionality we need to approach again with a fine-toothed comb, test, and affirm our assumptions in various ways.
