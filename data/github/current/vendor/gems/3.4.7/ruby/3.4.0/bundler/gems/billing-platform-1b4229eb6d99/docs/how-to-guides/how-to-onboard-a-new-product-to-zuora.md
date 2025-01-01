# How to Onboard a New Product to Zuora

This is a guide for how to set up a new product so that customers can be billed for usage through Zuora.

## Table of Contents

- [Terminology](#terminology)
- [Details](#details)
  - [Zuora meter creation](#zuora-meter-creation)
  - [Billing Platform Product Setup](#billing-platform-product-setup)
  - [Dotcom Product Setup](#dotcom-product-setup)
  - [Add Zuora rate plan to all existing subscriptions](#add-zuora-rate-plan-to-all-existing-subscriptions)
- [References](#references)

## Terminology

- **Sales-serve**: Invoiced customers
- **Self-serve**: Credit-card based customers

## Details

### Zuora meter creation

- [Financial Systems](https://github.com/github/financial-systems)/[#financial-systems](https://github.slack.com/archives/C0166UBAKBP) owns the process for creating new Zuora meters. Initiate this process by opening an issue to create a sales-serve and a self-serve rate plan in Zuora.
- The names of the sale-serve and self-serve rate plan charges should be the same and will be stored in billing-platform in the [Billing Platform Product Setup step](#billing-platform-product-setup).
- Example [issue](https://github.com/github/financial-systems/issues/4267)

### Billing Platform Product Setup

- Use the [stafftools products](https://admin.github.com/stafftools/billing/products) page to create a new product in billing-platform
- The `Zuora Usage Identifier` should be the name of the Zuora product rate plan charge created in the [Zuora Meter Creation step](#zuora-meter-creation)
  - This field is sent with the usage records during emission to Zuora and is used by Zuora to lookup the customer's subscription info
  - Example for actions: `GitHub Actions Usage`

### Dotcom Product Setup

- A metered `ProductUUID` needs to be created in dotcom, which will ensure the rate plan is included anytime a new self-serve subscription is created
- As of writing this, the `ProductUUID` can be created by making a twirp call:
  1. ssh into a production shell and `. vault-login`.
  2. Run `vault-secret --application billing-platform --key MONOLITH_TWIRP_HMAC_KEY` and copy the output
  3. Open an irb console:

      ```ruby
      require 'openssl'
      def request_hmac
        timestamp = Time.now.to_i.to_s
        hmac = OpenSSL::HMAC.hexdigest("sha256", 'REPLACE THIS WITH KEY FROM PREVIOUS STEP', timestamp)
        "#{timestamp}.#{hmac}"
      end
      request_hmac
      ```

  4. Connect to the dev vpn and make this request. Replace `{request-hmac}` in the header with the output from previous step.
      - Set the `zuora_product_id` and `zuora_product_rate_plan_id` to the ids from the _self-serve_ Zuora product.
      - Set the `product_type` to `"github.<product name>"`, ex: `github.actions`
      - Set the `effective_on` to any date in the future. This field is only used for validation and not stored.
      - A successful request returns `{"result": "ack"}`.

      ```shell
        curl --location 'https://internal-api.service.iad.github.net/internal/twirp/billing.products.v1.ZuoraProductAPI/SyncZuoraProducts' \
        --header 'Request-HMAC: {request_hmac}' \
        --header 'Content-Type: application/json' \
        --data '{
            "zuora_products": [
                {
                    "zuora_product_id": "REPLACE THIS",
                    "zuora_product_rate_plans": [
                        {
                            "zuora_product_rate_plan_id": "REPLACE THIS",
                            "effective_on": "2023-09-01T00:00:00.01Z"
                        }
                    ],
                    "product_type": "REPLACE THIS"
                }
            ]
        }'
      ```

  5. Go to the [stafftools metered products page](https://admin.github.com/stafftools/metered_product_uuids) and check the `ProductUUID` shows up there. If there are issues, try searching Splunk `index=prod-exceptions job=Billing::Zuora::SyncMeteredProductUuidsFromZuoraJob` and debug from there.
  6. Testing: try to sync an existing subscription and/or create a new subscription in production and check in Zuora that the new rate plan gets added to the subscription.

### Add Zuora rate plan to all existing subscriptions

- Request [Financial Systems](https://github.com/github/financial-systems)/[#financial-systems](https://github.slack.com/archives/C0166UBAKBP) to do a one time CSV upload to add the new rate plan to all existing sales-serve and self-serve subscriptions.
- Example issues:\
https://github.com/github/financial-systems/issues/4362 \
https://github.com/github/financial-systems/issues/4363

## References

- [Gitcoin Zuora documentation](https://github.com/github/gitcoin/tree/main/docs/technical/zuora)
