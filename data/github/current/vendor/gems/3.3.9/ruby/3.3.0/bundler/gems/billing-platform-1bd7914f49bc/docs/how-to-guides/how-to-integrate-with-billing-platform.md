# How to Integrate with Billing Platform

This is a guide for internal teams who are producing github products and wish to bill customers usage for those products. New to the billing platform? Check out the [Quick Start Guide](/docs/readme.md) to get an overview of the billing platform's general goals and concepts.

Planning to onboard a new metered product sku? Open an issue [here](https://github.com/github/gitcoin/issues/new?template=project-review.md) with the Billing team. Please visit [#billing-engineering](https://github.slack.com/archives/C04K3MLN1QE/) in slack to talk through this with the billing-platform team.

## Table of Contents

- [Details](#details)
  - [Prerequisites](#prerequisites)
  - [How to integrate your product with Billing Platform](#how-to-integrate-your-product-with-billing-platform)
- [References](#references)

## Details

[Business Planning](https://github.com/github/business-planning) has documented the how and why of a standardized [github product offering](https://docs.google.com/document/d/1pp06QSqkrFWNGtdaMPS7qVSLivhOwj07S68Dv6YmoM0/edit) which solidifies the ways products will interact with our down stream billing systems, ways we will provide free usage and what things apply in what situation. Billing platform is intending to conform to these standardized faculties.

### Prerequisites

#### Metered products

* New skus must be created in the Azure Commerce portal and each will receive an Azure meter id. This process is owned by [Business Planning](https://github.com/github/business-planning).
* New products must be added to Zuora. A "Zuora Usage Identifier" field will be used to identify them on Billing Platform. This field is the same as the name of a single rate plan charge added to the Zuora product. There's no need to create multiple SKUs (rate plan charges) per product. This process is owned by [Financial Systems](https://github.com/github/financial-systems).

#### Net New Customers and products

- Will be able to utilize the new platform natively

#### Existing Customers and Products

- Will need to receive new Terms of service (link pending)
- Utilize the new facilities for providing standardized free usage

### How to integrate your product with Billing Platform

The below does not describe the long term plan but rather the practical realities of the current pre-prod state of March 2023

1. *Free usage*: Product teams will need to work with billing and business planning to codify how entitlements and free accounts translates to discount and coupons, where in we focus on $ amounts not units of usages.
2. *Create products and skus*: Before a product may be billed there must be products/skus in the system to support it. Any additions, while automated, need to be coordinated with the [#billing-engineering](https://github.slack.com/archives/C04K3MLN1QE/) team, because there are multiple factors to consider (validating the Azure meter ids and the Zuora Usage Identifiers, replicating the products and skus to Proxima stamps, and etc). Be sure to have the pricing information available before requesting a new product and sku. Use [this issue template](https://github.com/github/gitcoin/issues/new?template=project-review.md) for the request.
3. *Plumb customerId*: Billing-platform is built on `customerId` as a [consolidated id](https://docs.google.com/document/d/1pCJMA41LFIPLjW_cNsFSHB4mXkYSd9hUvNmBOtqZiYg/edit#heading=h.k2l03jpwxkdg) for all things billing. Each usage message requires it, and its not plumbed through many products yet. Actions [added it](https://github.com/github/github/pull/260961) to their workflow launching so they would have it available to generate the usage messages.
4. *Create usage message*: To send usage to the billing platform, create and send [billingPlatform.v1.Usage](https://hydro.githubapp.com/schemas/billingplatform-v1-Usage) message from within your product where the usage is generated.

    - The `usage_uuid` field should be unique per hydro message. We use it to prevent the system processing a unique usage hydro message that as been sent multiple times (in error) by an upstream provider, or delivered more than once by Hydro.

    - The `sku` field in the usage message is different from the old billing system and we now send the plain text string as created in step 2, that describes the most granular thing being billed `actions_16_core_linux` or `git_lfs_storage`.

5. *Receive alerting messages*: As described in the [eng spec](https://docs.google.com/document/d/1r7UNncUO-h9WSTsBFNEmh0fW5MZqt4kkl7uYFTvsmTo/edit) billing will be generating hydro messages (not yet implemented) to indicate when a customer has hit their allotted budget and each product will need to react to that event based on how a customer has configured their budget. Options will include shutting down active usage, disallowing future usage or doing nothing.
6. *Support Non payment accounts* if a product teams wants to support "Free accounts* as they exist today they will have to process and respond to usage alerts and have faculties to stop on going usage so no more charges are incurred.
7. *Check usage is allowed*: The new billing api has an endpoint to check if a new usage event/job is allowable. See [canProceedWithUsage](https://github.com/github/billing-platform/blob/main/docs/reference/features/can-proceed-with-usage.md). Teams will ensure they call this api at any point where users are electively creating usage events (actions job, codspace start etc)
8. *UI*: Ensure your UI exposes budget status and processing abilities as applicable to customers. For example, "Code space creation is no longer allowed due to budget policy x"

## Outcome

* Your team will be calling [canProceedWithUsage](https://github.com/github/billing-platform/blob/main/docs/reference/features/can-proceed-with-usage.md) periodically to confirm a customer state before enabling metered product features.
* Your team will be ingesting metered usage to billing platform via [billingPlatform.v1.Usage](https://hydro.githubapp.com/schemas/billingplatform-v1-Usage)

## References

- For a deep dive on what/why/how of the new billing system see the [vNext Initative](https://github.com/github/gitcoin/issues/10307)
