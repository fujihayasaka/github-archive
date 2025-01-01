# Sentry

We use Sentry to log exceptions which are stored outside of the GitHub network. Because of this, we must avoid including any sensitive information in the exception message.

Docs:

* [identified sensitive data](https://thehub.github.com/engineering/development-and-ops/observability/exception-tracking/secure-exceptions/#identifying-your-sensitive-data)
* [breach remediation](https://thehub.github.com/engineering/development-and-ops/observability/exception-tracking/secure-exceptions#breach-remediation)

Schedule:

* A reminder will be posted in `#package-security-ops` once a month to check [Sentry](https://github.sentry.io/projects/attester/?project=4507781727059968) for any sensitive data.

This service handles action statement data. The following is potential sensitive data that should be scrubbed from exception reports:

* Repository names
* Package names
* Emails
* GitHub handles (PII)
* Environment variables stored in Vault (see `.env.example` for a list of environment variables)
