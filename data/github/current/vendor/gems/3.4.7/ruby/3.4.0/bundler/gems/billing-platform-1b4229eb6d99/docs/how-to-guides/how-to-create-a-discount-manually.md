# How to Create Discounts Manually

Until we create a UI to create discounts, here is how to manually create discounts.

## Table of Contents

- [Details](#details)
  - [Preconditions](#preconditions)
  - [Creating the HMAC token](#creating-the-hmac-token)
  - [Applying a discount](#applying-a-discount)
- [References](#references)

## Details

### Preconditions

- Connecting to dev-vpn is mandatory. Check out this [the hub post for details on connecting to the dev-vpn](https://thehub.github.com/security/security-operations/developer-vpn-access/).
- Have access to gitcoin's 1password vault

### Creating the HMAC token

In order to successfully call the billing-platform, you must be authenticated. This is accomplished using an HMAC token.

1. Open a terminal and jump into a ruby terminal using `irb`
2. Copy paste the following code, filling in the `<token-from-1-password>` string with the actual token from 1password which can be found by searching for "BillingPlatform HMAC Key"

    ```rb
    require "openssl"
    def request_hmac
    timestamp = Time.now.to_i.to_s
    hmac = OpenSSL::HMAC.hexdigest("sha256", "<key-from-1password>", timestamp)
    "#{timestamp}.#{hmac}"
    end
    ```

3. Save the output of `request_hmac` to insert as the value of the Request-HMAC header.

Note that this is time-based, so the token may expire quicker than you might think.

### Applying a Discount

Get your favorite API platform like Postman or Insomnia (or, cURL) ready and make sure you're connected to dev-vpn!

The information necessary to complete the call is detailed below.

| Key | Value |
|--------|--------|
| URL | `https://billing-platform-production.service.iad.github.net/twirp/billing_platform.api.v1.CustomerApi/CreateDiscount` |
| Method | POST |

Headers:

| Key | Value |
|--------|--------|
| Request-HMAC | The result from calling `request_hmac` |
| Content-Type | application/json |

Request Body (in json format):

| Key | Value |
|--------|--------|
| `customerId` | The customer id (e.g.`business.customer.id`) |
| `targetAmount`| Put a number if you want a _fixed_ dollar discount. Otherwise, leave it 0. |
| `percentageAmount`| Put a number between 0-100 if you want to apply a _percentage_ discount |
| `startDate` | Timestamp of when the discount should start being applied. Could be the beginning of the month for simplicity |
| `endDate` | Timestamp of when the discount should stop  being applied. Could be the end of the month for simplicity |
| `targets` | The discount target, comprised of a type and an id, see target table below. |

The following references the [DiscountTargetType](https://github.com/github/billing-platform/blob/355662f023696b793bfa3a1cd32dadbe949c6272/lib/models/discount.go#L57-L64).

| DiscountTargetType | Value |
|--------|--------|
| `SkuDiscount` | 1 |
| `ProductDiscount` | 2 |
| `RepoDiscount` | 3 |
| `OrgDiscount` | 4 |
| `EnterpriseDiscount` | 5 |

For example:
Setting the target to type `5` means that the discount applies to the entire enterprise with id of `1`.

```json5
"targets": [
    {
        "id": "1",
        "type": 5
    }
]
```

In the target example below, the discount would apply to the repository associated to the id `12345`.

```json5
"targets": [
    {
        "id": "12345",
        "type": 3
    }
]
```

Below is a complete example of what a request body could look like:

```json5
{
    "discount": {
        "customerId": "<customer-id>", // must be a string
        "targetAmount": 0, // any positive number
        "percentage": 10, // number between 0-100
        "startDate": 1688169791,
        "endDate": 1690761791,
        "targets": [
            {
                "id": "<target-id>", // the id of the target
                "type": 5 // discount target type
            }
        ]
    }
}
```

Double check that this is correct, and press "send". If successful, the response should return a `uuid` of the newly-created discount.

## References

- [Discounts doc](../reference/features/discounts.md)
