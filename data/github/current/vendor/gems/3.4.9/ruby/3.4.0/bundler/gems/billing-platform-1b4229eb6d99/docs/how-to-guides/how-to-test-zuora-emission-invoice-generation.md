# How to Test Zuora Emission and Invoice Generation

Customers that are not billed through Azure are billed through [Zuora](../reference/features/emissions/zuora-emissions.md).

## Table of Contents

- [Details](#details)
  - [How to setup the sandbox environment for Zuora testing](#how-to-setup-the-sandbox-environment-for-zuora-testing)

## Details

### How to setup the sandbox environment for Zuora testing

Billing-platform is integrated wth Zuora API Sandbox in development. You can follow these steps to test invoice generation and emission to Zuora for dev work.

1. Setup the Zuora account
   - Go to [API Sandbox](https://apisandbox.zuora.com/platform/webapp) and find an existing account or [create a new account](https://github.com/github/gitcoin/blob/main/docs/playbook/howto/how-to-create-an-invoiced-account.md)
   - Make sure the subscription has the [GitHub Usage Product](https://apisandbox.zuora.com/apps/Product.do?method=view&id=8ad08e1a8876289c01887885c7dd14de) and the [GitHub Actions Usage rate plan](https://apisandbox.zuora.com/apps/Product.do?method=view&id=8ad08e1a8876289c01887885c7dd14de#8ad085e2887628ae01887887ec792391). If creating a new subscription, these can be added at the time of creation:
   ![create zuora subscription](/docs/images/zuora_subscription_creation.png) <br/><br/>
   Or if using an existing subscription, the product and rate plan can be added by creating an amendment (amendment type = New Product):
   ![zuora subscription amendment](/docs/images/zuora_subscription_amendment.png)
   - Note the account number (ex: `A0102180425`)

2. Run `script/produce` to generate usage and an active invoice record for a customer. You can verify the active invoice record was created with this query:

    ```sql
    select * from c where c.id = "customer:9370725:invoices:2023:7"
    and c.partitionKey = "invoices:active:2023:7"
    ```

3. Update the customer record in billing-platform if necessary to make sure these 2 fields are set:

    ```go
      BillingTarget: 1 // 1 = Zuora
      ZuoraAccountNumber: "A0102180425", // set this to the account number from step 1
    ```

4. Generate the invoice and emit to Zuora
    - If developing in a billing-platform codespace, run

      ```shell
      # -c = customer id or cost center uuid, omit if generating for all customers
      # -y = year
      # -m = month
      script/schedule-invoice-generation -c 9370725 -y 2023 -m 7
      ```

      The resulting invoice can be queried in Cosmos like this:

        ```sql
        select * from c where c.id = "customer:9370725:invoices:2023:7"
      and c.partitionKey = "customer:9370725:invoices"
        ```

    - Or if developing in a dotcom codespace with billing-platform running, the invoice can be generated and viewed from the enterprise's stafftools invoices page (`github.localhost/stafftools/enterprises/<slug>/billing/invoices`). This is available for testing in production too.

5. If emission was successful the usage should show up under the Usage section in the Zuora account. \
If the usage was for a cost center, click on the Status column to view more details and check that the Cost Center field matches the name of the cost center in billing-platform.
