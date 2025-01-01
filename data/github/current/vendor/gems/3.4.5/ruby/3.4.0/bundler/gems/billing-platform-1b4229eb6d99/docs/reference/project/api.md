# API

This document describes the Billing Platform API, which is set up with Twirp. It provides examples for interacting with the API using cURL.

## Table of Contents

- [Details](#details)
  - [Setup the API Project](#setup-the-api-project)
  - [Twirp](#twirp)
  - [API Requests via cURL](#api-requests-via-curl)
  - [HMAC Auth](#hmac-auth)
- [Examples](#examples)
  - [API Example: Get usage](#api-example-get-usage)
  - [API Example: Get Active in Bucket](#api-example-get-active-in-bucket)
  - [API Example: Get Active in Bucket and Period](#api-example-get-active-in-bucket-and-period)
  - [API Example: Get Pricing](#api-example-get-pricing)
  - [API Example: Upsert Pricing](#api-example-upsert-pricing)
  - [API Example: Get Customer](#api-example-get-customer)
  - [API Example: Upsert Customer](#api-example-upsert-customer)
  - [API Example: Get Budget](#api-example-get-budget)
  - [API Example: Get Budget State](#api-example-get-budget-state)
  - [API Example: Upsert Budget](#api-example-upsert-budget)
- [References](#references)

## Details

### Setup the API project

```bash
script/build
script/api
```

### Twirp

Twirp generates path prefixes based on how you setup your API(s). This could mean having one large API broken up by module, or individual APIs by use case.

For Billing Platform we've opted to implement multiple APIs per use case. Once
the server starts, you will see log messages noting the path prefix to access
individual APIs.

```bash
time=... level=info msg="Usage API" prefix=/twirp/billing_platform.api.v1.UsageApi/
```

### API Requests via cURL

The Twirp Docs outline how to access APIs via [cURL](https://twitchtv.github.io/twirp/docs/curl.html).

Here is the generic structure Twirp uses to autogenerates API routes:

```bash
<baseURL>[<prefix>]/<package>.<Service>/<Method>
```

For Billing Platform, that manifests as:

```bash
http://localhost:8989/twirp/billing_platform.api.v1.UsageApi/GetUsage
```

Using this within a cURL request (data not provided):

```bash
curl -X POST \
 --header "Content-Type: application/json" \
 --data '{}' \
 http://localhost:8989/twirp/billing_platform.api.v1.UsageApi/GetUsage
```

### HMAC Auth

We use HMAC for service to service authentication (read more [on The Hub](https://thehub.github.com/epd/engineering/dev-practicals/secure-coding/secure-coding-general/service-to-service-auth/)).
In development mode we set the `SKIP_HMAC` env var to be able to query the local API without providing the HMAC header. In order to test the auth you need to set `SKIP_HMAC=false` in `dev.env` and restart the api server. After that you need to send an additional header with every request:

```bash
curl -X POST \
  --url http://localhost:8989/twirp/billing_platform.api.v1.UsageApi/GetUsageTotal \
  --header 'Content-Type: application/json' \
  --header 'Request-HMAC: 1676969030.xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' \
  --data '{}'
```

To generate a valid value for that header, run `make gen-hmac-header` and copy the output.

## Examples

### API Example: Get usage

```bash
curl -X POST 'http://localhost:8989/twirp/billing_platform.api.v1.UsageApi/GetUsageTotal' \
--header 'Content-Type: application/json' \
--data-raw '{
    "sku": "beta-self-hosted-runner",
    "year": 2023,
    "month": 1,
    "day": 1,
    "hour": 1,
    "billingPeriod": 1,
    "usageEntityId": "1"
}'
```

### API Example: Get Active in Bucket

```bash
curl -X POST 'http://localhost:8989/twirp/billing_platform.api.v1.AdminApi/GetActiveInBucket' \
--header 'Content-Type: application/json' \
--data-raw '{
    "billingPeriod": 1
}'
```

### API Example: Get Active in Bucket and Period

```bash
curl -X POST 'http://localhost:8989/twirp/billing_platform.api.v1.AdminApi/GetActiveInBucketAndPeriod' \
--header 'Content-Type: application/json' \
--data-raw '{
    "billingPeriod": 1,
    "year": 1,
    "month": 1,
    "day": 1,
    "hour": 1
}'
```

### API Example: Get Pricing

```bash
curl -X POST 'http://localhost:8989/twirp/billing_platform.api.v1.PricingApi/GetPricing' \
--header 'Content-Type: application/json' \
--data-raw '{
    "sku": "beta-self-hosted-runner"
}'
```

### API Example: Upsert Pricing

```bash
curl -X POST 'http://localhost:8989/twirp/billing_platform.api.v1.PricingApi/UpsertPricing' \
--header 'Content-Type: application/json' \
--data-raw '{
    "pricing": {
        "sku": "copilot-individual-monthly",
        "product": "GitHub Copilot",
        "price": 19.99
    }
}'
```

### API Example: Get Customer

```bash
curl -X POST 'http://localhost:8989/twirp/billing_platform.api.v1.CustomerApi/GetCustomer' \
--header 'Content-Type: application/json' \
--data-raw '{
    "customerId": "1"
}'
```

### API Example: Upsert Customer

```bash
curl -X POST 'http://localhost:8989/twirp/billing_platform.api.v1.CustomerApi/UpsertCustomer' \
--header 'Content-Type: application/json' \
--data-raw '{
    "customer": {
        "customerId": "2"
    }
}'
```

### API Example: Get Budget

```bash
curl -X POST 'http://localhost:8989/twirp/billing_platform.api.v1.CustomerApi/GetBudget' \
--header 'Content-Type: application/json' \
--data-raw '{
    "key": {
        "customerId": "1",
        "targetType": 1,
        "targetId": "1",
        "pricingTargetType": 1,
        "pricingTargetId": ""
    }
}'
```

### API Example: Get Budget State

```bash
curl -X POST 'http://localhost:8989/twirp/billing_platform.api.v1.CustomerApi/GetBudgetState' \
--header 'Content-Type: application/json' \
--data-raw '{
    "key": {
        "customerId": "1",
        "targetType": 1,
        "targetId": "1",
        "pricingTargetType": 1,
        "pricingTargetId": ""
    },
    "year": 2023,
    "month": 2
}'
```

### API Example: Upsert Budget

```bash
curl -X POST 'http://localhost:8989/twirp/billing_platform.api.v1.CustomerApi/UpsertBudget' \
--header 'Content-Type: application/json' \
--data-raw '{
    "budget": {
        "targetAmount": 100.00,
        "key": {
            "customerId": "1",
            "targetType": 1,
            "targetId": "1",
            "pricingTargetType": 1,
            "pricingTargetId": ""
        }
    }
}'
```

## References

- [The Hub: HMAC Auth](https://thehub.github.com/epd/engineering/dev-practicals/secure-coding/secure-coding-general/service-to-service-auth/)
