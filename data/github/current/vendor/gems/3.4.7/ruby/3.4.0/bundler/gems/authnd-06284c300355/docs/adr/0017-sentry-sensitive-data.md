# 17. Sensitive Data Filtering from Logs

Date: 2020-08-13

*NOTE: This was a non-ADR design doc from the Wall-E experiment that has been absorbed in as an ADR. It's number does not represent the actual order in which it was created, and it's format differs from the others.*

## Status

Accepted

## Context

We log exceptions to Sentry.
As per our policies on [sensitive data in logs/exceptions/etc.](https://thehub.github.com/engineering/development-and-ops/observability/sentry/secure-exceptions/#consideration) we need to document the sensitive data we expect to handle and which data should be excluded from logs.

## Classifications

### Sensitive data

This data should be filtered out from exception messages and error logs.

* Repository Name (Private repo names are not usually available)
* Passwords
* URLs
* Security Tokens:
  * OAuth
  * GitHub App JWTs

### Public data that does not need to be filtered

This data does not need to be filtered out (this is not an exhaustive list).

* User login name
