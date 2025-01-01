# Review Sentry Errors

## Background

As part of the best security practices at GitHub, we are required to review our Sentry entries for any potential PII data leakage. There is a monthly [Slack reminder workflow](https://github.com/github/package-security/blob/main/configs/slack_workflows/review_sentry_errors.slackworkflow)
that posts to `#package-security-ops`.

## Process

1. Review the [TMA Sentry doc](https://github.com/github/trust-metadata-api/blob/main/docs/sentry.md) for our list of potential PII values
2. Access the [TMA Sentry Dashboard](https://sentry.io/organizations/github/projects/trust-metadata-api/?project=4504079440740352)
3. Review any exceptions for the last 30 days

* If you notice any sensitive data has been sent to Sentry, follow the [breach remediation](https://thehub.github.com/engineering/development-and-ops/observability/exception-tracking/secure-exceptions#breach-remediation) in our [TMA Sentry doc](https://github.com/github/trust-metadata-api/blob/main/docs/sentry.md)
* If there are no issues, mark the reminder message in `#package-security-ops` with a green check emoji reaction or comment a thread that you have reviewed it this month.
