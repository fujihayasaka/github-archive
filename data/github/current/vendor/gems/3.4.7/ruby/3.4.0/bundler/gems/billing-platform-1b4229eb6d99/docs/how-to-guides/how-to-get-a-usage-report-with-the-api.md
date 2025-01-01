# How to Get a Usage Report with the API

The Get Usage Report endpoint is a billing API that queries and returns aggregated usage information for billing customers from billing platform. This serves as a public REST API to query for customers in Dotcom. The public API lives with other Billing APIs in [Dotcom](https://github.com/github/github/blob/master/app/api/billing.rb).

We offer usage report APIs for individuals, organizations and enterprises.

> [!NOTE]
> This API serves less granular data than the usage report button in the UI. See [Usage Reports](../reference/features/usage-reports.md) for more information on how UI usage reports are generated and delivered.

- [Details](#details)
  - [Getting a usage report with the API locally](#getting-a-usage-report-with-the-api-locally)
  - [Getting a usage report with the API in production](#getting-a-usage-report-with-the-api-in-production)
  - [Examples](#examples)
- [References](#references)

## Details

### Getting a usage report with the API locally

- Start dotcom server
- Ensure the customer is onboarded to billing platform ([use stafftools to sync](http://github.localhost/stafftools/billing/onboard_billing_platform_customer))
- Start billing platform
- Create a local personal access token classic in dev with enterprise admin permissions and use that when making a curl request

```bash
curl -L \
  -H "Accept: application/vnd.github+json" \
  -H "Cache-Control: no-cache" \
  -H "Authorization: Bearer PERSONAL_ACCESS_TOKEN_HERE" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  http://api.github.localhost/enterprises/github-inc/settings/billing/usage
```

See below for specifying [parameters](get-usage-report-api.md#parameterized-examples)

### Getting a usage report with the API in production

Via [GH CLI](https://cli.github.com/)

#### Individual

```bash
gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /users/monalisa/settings/billing/usage
```

#### Organization

```bash
gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /orgs/dsp-testing/settings/billing/usage
```

#### Enterprise

```bash
gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /enterprises/avocado-corp/settings/billing/usage
```

The endpoint also accepts optional parameters for specifying usage for year, month, day and hour. If year is omitted we default to the current year. If other fields are omitted we use the first day, first month or first hour.

Valid params are `year`, `month`, `day`, `hour` all in integer format.

### Examples

Example to pass in year:

```bash
gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /enterprises/avocado-corp/settings/billing/usage\?year\=2023
```

Example to pass in year & month:

```bash
gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /enterprises/avocado-corp/settings/billing/usage\?year\=2023\&month\=9
```

Example to pass in year, month, day & hour:

```bash
gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /enterprises/avocado-corp/settings/billing/usage\?year\=2023\&month\=10\&day\=13\&hour\=17
```

#### Example Successful Response

```json
{
  "usageItems": [
    {
      "date": "2023-10-03T15:46:02Z",
      "product": "copilot",
      "sku": "Copilot for Business",
      "quantity": 7.48387096,
      "unitType": "UserMonths",
      "pricePerUnit": 19.0,
      "grossAmount": 142.19354824,
      "discountAmount": 0.0,
      "netAmount": 142.19354824,
      "organizationName": "copilot-testing-billing-2",
      "repositoryName": "",
    },
    {
      "date": "2023-10-10T00:15:55Z",
      "product": "copilot",
      "sku": "Copilot for Business",
      "quantity": 0.709677419,
      "unitType": "UserMonths",
      "pricePerUnit": 19.0,
      "grossAmount": 13.483870961,
      "discountAmount": 0.0,
      "netAmount": 13.483870961,
      "organizationName": "lyric-org-admin-testing",
      "repositoryName": "",
    }
  ]
}
```

#### Example Unauthorized Response

Our usage report APIs restrict access to customers that are billed via billing platform. If a customer is not billed via billing platform, the API will return a 403.

```json
{
  "message": "No access to billing usage data.",
  "documentation_url": "https://docs.github.com/rest/billing/billing#get-billing-usage-report-for-an-organization",
  "status": "403"
}
```

## References

- [Billing Platform Usage Report Dashboard](https://app.datadoghq.com/dashboard/htb-kx2-zb7/billing-platform-usage-report-api?refresh_mode=sliding&from_ts=1696953734111&to_ts=1697558534111&live=true)
- [Public usage report API documentation](https://docs.github.com/en/enterprise-cloud@latest/rest/enterprise-admin/billing?apiVersion=2022-11-28#get-billing-usage-report-for-an-enterprise)
