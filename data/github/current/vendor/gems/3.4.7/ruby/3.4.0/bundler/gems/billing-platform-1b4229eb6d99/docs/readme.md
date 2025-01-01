# Billing Platform

## Introduction

The billing platform is the codebase and single source of truth for all of the logic surrounding billing of metered usage / consumptive products. This includes consumptive product configuration, customer budgets, and *all* usage data regardless of the final price of the usage. For example, actions usage on public repos hasn't always been reported to billing, but even public repo "free" consumptive usage will be reported to the billing platform.

The billing platform is an API only service. The GUI to make configuration updates and view usage is done in GitHub stafftools and on customer's GitHub billing pages. These all make API calls to the platform for data access and CRUD operations. For example the metered usage product hub is accessible at https://admin.github.com/stafftools/billing/products.

## Getting Started

### I'm a developer working on Billing Platform, where do I start?

- Read the "Main Concepts" below to get a basic overview of billing concepts related to the Billing Platform
- Check out [Run Billing Platform in a Dotcom Codespace](./tutorials/run-billing-platform-in-dotcom-codespaces.md) to get Billing Platform running
- Review documentation in the Reference folder to understand the features of the product, tools that the Billing Platform uses, and specifics about this project

### I'm a developer integrating a product with Billing Platform, where do I start?

- Read [How to integreate with Billing Platform](./how-to-guides/how-to-integrate-with-billing-platform.md)
- Come chat with the team in [#billing-engineering](https://github-grid.enterprise.slack.com/archives/C04K3MLN1QE)

## Main Concepts

### Product

A "Product" refers to a set of similar SKUs that are variations of a similar core concept. For example GitHub Actions or GitHub Copilot are both products. The billing platform aims to contain no product specific logic. Due to tight timelines in the past, when new products were introduced, it often involved the billing team writing new code that was specific to that new product. As more and more products were introduced, having product specific logic ended up becoming a bottleneck as similar code had to be rewritten for addition. The billing platform aims to be product agnostic such that new products can be added completely from a web GUI without any code changes or new deploys. All product specific logic is generalized into configuration that is stored in the billing platform's data store.

### SKU

A SKU is a variation of a product offered at a specific unit price. For example, GitHub Actions offers a SKU for 2 core linux machines, a SKU for windows machines, a SKU for macOS machines, etc. Product teams have access to the billing platform's product hub where they can add and update SKUs for their product as needed.

### Metered Usage

Metered usage or consumptive usage is when a customer is charged based on how much of a product they use. The usage will be measured using a specific unit of measure and it is multiplied by a unit price. For example, we charge $0.008 per minute that a GitHub Action is running.

There are two types of metered usage that the billing platform is concerned with: static usage and watermark usage.

#### Static Usage

Static usage is usage in which the quantity reported to the billing-platform is the exact quantity that has been consumed. Almost all "compute" usage falls into this category. For example a customer may have used 5 minutes of actions compute on a 2 core linux machine or they may have run a Codespace for 1 hour. In both cases the exact quantity of already consumed usage is reported to the billing platform.

#### Watermark Usage

Watermark usage is usage in which the quantity reported to the billing platform represents a change in a usage level, and the billing platform calculates totals based on the amount of time in which a certain quantity is maintained. An example of this is storage usage. For example, when a customer uploads a new package version to GitHub Package Registry, the billing platform would be notified that the storage level has been increased by the size of that package. If a package version is deleted, then the billing platform would be notified that the storage level has been decreased by the appropriate amount. The billing platform will calculate the total amount of that the storage in a unit of Storage * Time (like GB-Days) based on the amount of time the storage value was at each level.

[For more details on Watermark products, check out this doc](./reference/features/product-types/watermark.md).

#### High Watermark Usage

Watermark Usage can be configured as *High* Watermark Usage. This is useful for products such as GHAS or Copilot for Business in which a decrease of usage does't become recognized until the next billing period starts. For example, if a customer starts the month using 1 copilot licenses, increases the number of used licenses to 2 after 15 days, and then decreases the number of used licenses back to 1 after the 20th day, the billing platform will charge the customer 1 User *15 Days for the first 15 days of the month and 2 Users* 15 Days for the last 15 days of the month. The decrease back down to 1 user only becomes effective at the start of the next billing cycle.

[For more details on High Watermark products, check out this doc](./reference/features/product-types/high-watermark.md).

### Discounts / Coupons

There are a number of reasons in which the business may want to offer a SKU at a price less than the configured unit price. For example, certain SKUs might be entirely free if they meet certain criteria (like free standard actions runners on public repos), or they might be free up until a certain point to encourage trials of their use (like the first $50 of actions usage on private repos is free, (this concept was previously known as Entitlements)). The record of any of these scenarios are configured in the Product Hub via discounts and coupons.

[For more details on discounts, check out this doc](./reference/features/discounts.md).

### Budgets

Customers can set budgets for their enterprise or for individual organizations, repositories, or users. [For more details on budgets, check out this doc](./reference/features/budgets.md).

### Cost Centers

Cost centers can group the metered usage of a department within an enterprise. They can be made up of multiple resources, including organizations, repositories, or users. [For more details on cost centers, check out this doc](./reference/features/cost-centers.md).
