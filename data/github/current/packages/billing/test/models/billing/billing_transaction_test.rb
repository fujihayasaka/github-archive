# typed: true
# frozen_string_literal: true

require "test_helper"

class BillingTransactionTest < GitHub::TestCase
  include DogstatsTestHelpers

  include GitHub::BillingTest
  include GitHub::SponsorsZuoraTestHelper
  include GitHub::Billing::CurrencyTestHelper
  include GitHub::BrainTree::TestHelper
  include GitHub::ZuoraTestHelper

  fixtures do
    @user = create(:credit_card_user, login: "mfdoom", billed_on: ::GitHub::Billing.today + 1.day,
      plan_subscription: create(:billing_plan_subscription))
    @plan_subscription = @user.plan_subscription
    @transaction = create :billing_transaction
    @transaction.statuses.create amount_in_cents: 1200, status: :authorized
  end

  setup do
    synchronize_github_products_to_zuora
    setup_currency_exchange
  end

  context "created_at_or_after scope" do
    test "returns only billing transactions created on or after the given time" do
      three_day_xact = travel_to(3.days.ago) { create(:billing_transaction) }
      week_xact = travel_to(1.week.ago) { create(:billing_transaction) }
      day_xact = travel_to(1.day.ago) { create(:billing_transaction) }

      result = Billing::BillingTransaction.created_at_or_after(three_day_xact.created_at)
        .where(id: [three_day_xact, week_xact, day_xact])

      assert_includes result, day_xact
      assert_includes result, three_day_xact
      refute_includes result, week_xact
    end
  end

  context "#multiple_products?" do
    test "returns true when the billing transaction has line items representing different subscribables" do
      xact = create(:billing_transaction)
      create(:billing_transaction_line_item, :marketplace_listing, billing_transaction: xact)
      create(:billing_transaction_line_item, :product_uuid, billing_transaction: xact)
      assert_predicate xact, :multiple_products?
    end

    test "returns false when the billing transaction has a single line item" do
      xact = create(:billing_transaction)
      create(:billing_transaction_line_item, :marketplace_listing, billing_transaction: xact)
      refute_predicate xact, :multiple_products?
    end

    test "returns false when the billing transaction has a sponsorship and its fee" do
      xact = create(:billing_transaction)
      tier = create(:sponsors_tier, :approved_sponsors_listing)
      create(:billing_transaction_line_item, :sponsors, billing_transaction: xact, subscribable: tier)
      create(:billing_transaction_line_item, :sponsors_fee, billing_transaction: xact, subscribable: tier)
      refute_predicate xact, :multiple_products?
    end

    test "returns true when the billing transaction has two sponsorships and their fees" do
      xact = create(:billing_transaction)
      tier1, tier2 = create_pair(:sponsors_tier, :approved_sponsors_listing)
      create(:billing_transaction_line_item, :sponsors, billing_transaction: xact, subscribable: tier1)
      create(:billing_transaction_line_item, :sponsors_fee, billing_transaction: xact, subscribable: tier1)
      create(:billing_transaction_line_item, :sponsors, billing_transaction: xact, subscribable: tier2)
      create(:billing_transaction_line_item, :sponsors_fee, billing_transaction: xact, subscribable: tier2)
      assert_predicate xact, :multiple_products?
    end
  end

  context "created_before scope" do
    test "returns only billing transactions created before the given time" do
      three_day_xact = travel_to(3.days.ago) { create(:billing_transaction) }
      week_xact = travel_to(1.week.ago) { create(:billing_transaction) }
      day_xact = travel_to(1.day.ago) { create(:billing_transaction) }

      result = Billing::BillingTransaction.created_before(three_day_xact.created_at)
        .where(id: [three_day_xact, week_xact, day_xact])

      refute_includes result, day_xact
      refute_includes result, three_day_xact
      assert_includes result, week_xact
    end
  end

  context "#stafftools_url" do
    test "returns relevant URL for viewing the transaction in stafftools" do
      assert_equal "http://#{GitHub.host_name}/stafftools/users/#{@transaction.user}/history",
        @transaction.stafftools_url
    end
  end

  # see also tests in packages/github_sponsors/test/models/billing/billing_transaction/sponsors_dependency_test.rb
  context "#zuora_payment_gateway" do
    test "returns 'Stripe v3' when using a credit card" do
      transaction = build(:billing_transaction, payment_type: :credit_card)
      assert_equal Billing::Zuora::PaymentGateway::STRIPE_V3, transaction.zuora_payment_gateway
    end

    test "returns 'Paypal' when using PayPal" do
      transaction = build(:billing_transaction, payment_type: :paypal)
      assert_equal Billing::Zuora::PaymentGateway::PAYPAL, transaction.zuora_payment_gateway
    end

    test "returns nil when billing transaction has no payment type" do
      transaction = build(:billing_transaction, payment_type: nil)
      assert_nil transaction.zuora_payment_gateway
    end
  end

  context "#build_refund_transaction" do
    test "sets the refund transaction's plan name to the billable entity current plan name" do
      transaction = create(:billing_transaction, :business_owned, plan_name: "business")
      billable_entity = transaction.billable_entity
      assert_equal "business_plus", billable_entity.plan_name

      refund_transaction = transaction.build_refund_transaction(amount_in_cents: 100, refund_reference_id: "abc", platform_transaction_id: "P123")

      assert_equal billable_entity.plan_name, refund_transaction.plan_name
    end

    test "works when the billable entity does not exist" do
      transaction = Billing::BillingTransaction.new(amount_in_cents: 100)
      assert_nil transaction.billable_entity

      refund_transaction = transaction.build_refund_transaction(amount_in_cents: 100, refund_reference_id: "abc", platform_transaction_id: "P123")

      assert refund_transaction
    end
  end

  context "#refundable?" do
    test "is false when the associated user has been deleted" do
      transaction = create(:billing_transaction)
      transaction.live_user.delete
      transaction.reload
      refute_predicate transaction, :refundable?
    end

    test "is false when the transaction is a credit balance adjustment" do
      # Technically we can revert a CBA but the functionality hasn't been implemented so we just say it's not refundable
      transaction = create(:billing_transaction, :credit_balance_adjustment)
      refute_predicate transaction, :refundable?
    end

    test "true for businesses" do
      transaction = create(:billing_transaction, :business_owned)
      assert_predicate transaction, :refundable?
    end
  end

  context "#credit_balance_adjustment_transaction?" do
    test "returns true when the transaction ID starts with CBA-" do
      transaction = create(:billing_transaction, :credit_balance_adjustment)

      assert transaction.credit_balance_adjustment_transaction?
    end

    test "returns false when the transaction ID does not start with CBA-" do
      transaction = create(:billing_transaction, transaction_id: "abc123")

      refute transaction.credit_balance_adjustment_transaction?
    end

    test "returns false when transaction ID is nil" do
      transaction = create(:billing_transaction, :failed, transaction_id: nil)

      refute_predicate transaction, :credit_balance_adjustment_transaction?
    end
  end

  # see also tests in packages/github_sponsors/test/models/billing/billing_transaction/sponsors_dependency_test.rb
  context "#log_recurring_charge" do
    test "does not fail if tax item creation is throttled" do
      plan = GitHub::Plan.pro
      @user.update!(plan: plan)
      uuid = plan.product_uuid(@user.plan_duration)
      charge = uuid.charges.first
      assert charge, "No charge found for #{uuid.inspect}"

      copilot_uuid = create(:billing_product_uuid, :copilot_enterprise)

      service_start_date = "2022-09-22"
      service_end_date = "2022-10-21"
      # Testing all 3 different item types subscription items, github plan, and usage
      invoice_items = [
        # GitHub Plan
        Billing::Zuora::InvoiceItem.new({
          "id" => SecureRandom.alphanumeric(32),
          "subscriptionId" => @plan_subscription.zuora_subscription_id,
          "unitPrice" => charge.price,
          "chargeAmount" => charge.price,
          "chargeId" => SecureRandom.alphanumeric(32),
          "chargeName" => charge.name,
          "unitOfMeasure" =>  "",
          "quantity" => 1,
          "subscriptionName" => @plan_subscription.zuora_subscription_number,
          "productRatePlanChargeId" => charge.zuora_product_rate_plan_charge_id,
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "taxationItems" => {
            "data" => [zuora_taxation_items_data_attributes(name: "GitHub Tax")]
          }
        }),
        # Usage Item
        Billing::Zuora::InvoiceItem.new({
          "id" => SecureRandom.alphanumeric(32),
          "subscriptionId" => @plan_subscription.zuora_subscription_id,
          "unitPrice" => 1.0,
          "chargeAmount" => 1.0,
          "chargeId" => SecureRandom.alphanumeric(32),
          "chargeName" => copilot_uuid.name,
          "unitOfMeasure" =>  "",
          "quantity" => 1,
          "subscriptionName" => @plan_subscription.zuora_subscription_number,
          "productRatePlanChargeId" => copilot_uuid.zuora_product_rate_plan_charge_ids[:flat],
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "taxationItems" => {
            "data" => [zuora_taxation_items_data_attributes(name: "Usage Tax")]
          }
        }),
      ]

      # Simulate a throttling error when creating tax items
      Billing::BillingTransaction::LineItem
        .any_instance
        .stubs(:create_tax_item_from_source)
        .raises(Freno::Throttler::Error.new)

      billing_transaction = Billing::BillingTransaction.new(
        amount_in_cents: charge.price,
        plan_subscription: @plan_subscription,
      )

      assert_difference "Billing::BillingTransaction::TaxItem.count", 0 do
        assert_difference "Billing::BillingTransaction::LineItem.count", 2 do
          billing_transaction.log_recurring_charge(
            billable_entity: @user,
            invoiced_items: invoice_items,
            charge_type: "recurring-charge"
          )
        end
      end
      billing_transaction.reload

      github_invoice_item = invoice_items[0]
      usage_invoice_item = invoice_items[1]

      refute_nil billing_transaction.line_items.detect { |li| li.description.include?(github_invoice_item.charge_name) }
      refute_nil billing_transaction.line_items.detect { |li| li.description.include?(usage_invoice_item.charge_name) }

      # Logs metrics for the total amount of tax and items created
      assert_dogstats_increment(2, "billing.billing_transaction.tax_item_creation_throttled")
      tags = ["success:false"]
      assert_dogstats_count(2, "billing.billing_transaction.tax_item.diff", tags: tags)
      assert_dogstats_count(2, "billing.billing_transaction.tax_item.created", tags: tags)
      assert_dogstats_count(2, "billing.billing_transaction.tax_item.cream", tags: tags)
    end

    test "creates tax items for invoices that contain the data" do
      plan = GitHub::Plan.pro
      @user.update!(plan: plan)
      uuid = plan.product_uuid(@user.plan_duration)
      charge = uuid.charges.first
      assert charge, "No charge found for #{uuid.inspect}"

      approved_listing = create(:marketplace_listing, :verified)
      approved_listing_plan = create(:marketplace_listing_plan, :published, listing: approved_listing)
      create(
        :billing_subscription_item,
        plan_subscription: @plan_subscription,
        subscribable: approved_listing_plan,
        quantity: 1,
      )
      marketplace_uuid = create(:billing_product_uuid, :marketplace_listing_plan, listing_plan: approved_listing_plan)

      copilot_uuid = create(:billing_product_uuid, :copilot_enterprise)

      service_start_date = "2022-09-22"
      service_end_date = "2022-10-21"
      # Testing all 3 different item types subscription items, github plan, and usage
      invoice_items = [
        # GitHub Plan
        Billing::Zuora::InvoiceItem.new({
          "id" => SecureRandom.alphanumeric(32),
          "subscriptionId" => @plan_subscription.zuora_subscription_id,
          "unitPrice" => charge.price,
          "chargeAmount" => charge.price,
          "chargeId" => SecureRandom.alphanumeric(32),
          "chargeName" => charge.name,
          "unitOfMeasure" =>  "",
          "quantity" => 1,
          "subscriptionName" => @plan_subscription.zuora_subscription_number,
          "productRatePlanChargeId" => charge.zuora_product_rate_plan_charge_id,
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "taxationItems" => {
            "data" => [zuora_taxation_items_data_attributes(name: "GitHub Tax")]
          }
        }),
        # Subscription Item
        Billing::Zuora::InvoiceItem.new({
          "id" => SecureRandom.alphanumeric(32),
          "subscriptionId" => @plan_subscription.zuora_subscription_id,
          "unitPrice" => charge.price,
          "chargeAmount" => charge.price,
          "chargeId" => SecureRandom.alphanumeric(32),
          "chargeName" => approved_listing.name,
          "unitOfMeasure" =>  "",
          "quantity" => 1,
          "subscriptionName" => @plan_subscription.zuora_subscription_number,
          "productRatePlanChargeId" => marketplace_uuid.zuora_product_rate_plan_charge_ids[:flat],
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "taxationItems" => {
            "data" => [zuora_taxation_items_data_attributes(name: "Marketplace Tax")]
          }
        }),
        # Usage Item
        Billing::Zuora::InvoiceItem.new({
          "id" => SecureRandom.alphanumeric(32),
          "subscriptionId" => @plan_subscription.zuora_subscription_id,
          "unitPrice" => 1.0,
          "chargeAmount" => 1.0,
          "chargeId" => SecureRandom.alphanumeric(32),
          "chargeName" => copilot_uuid.name,
          "unitOfMeasure" =>  "",
          "quantity" => 1,
          "subscriptionName" => @plan_subscription.zuora_subscription_number,
          "productRatePlanChargeId" => copilot_uuid.zuora_product_rate_plan_charge_ids[:flat],
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "taxationItems" => {
            "data" => [zuora_taxation_items_data_attributes(name: "Usage Tax")]
          }
        }),
      ]

      billing_transaction = Billing::BillingTransaction.new(
        amount_in_cents: charge.price,
        plan_subscription: @plan_subscription,
      )

      assert_difference "Billing::BillingTransaction::TaxItem.count", 3 do
        assert_difference "Billing::BillingTransaction::LineItem.count", 3 do
          billing_transaction.log_recurring_charge(
            billable_entity: @user,
            invoiced_items: invoice_items,
            charge_type: "recurring-charge"
          )
        end
      end
      billing_transaction.reload

      github_invoice_item = invoice_items[0]
      marketplace_invoice_item = invoice_items[1]
      usage_invoice_item = invoice_items[2]

      github_line_item = T.must(billing_transaction.line_items.detect { |li| li.description.include?(github_invoice_item.charge_name) })
      assert_equal 1, github_line_item.tax_items.count
      github_tax_item = T.must(github_line_item.tax_items.first)
      zuora_github_tax_item = T.must(github_invoice_item.taxation_items.first)
      assert_equal "GitHub Tax", github_tax_item.name
      assert_equal zuora_github_tax_item.tax_amount.cents, github_tax_item.amount_in_cents
      assert_equal zuora_github_tax_item.id, github_tax_item.source_id
      assert_equal "zuora", github_tax_item.source_name

      # Imporant: while we are testing taxation of marketplace line items here
      # this doesn't mean marketplace or sponsor products are taxable. This is just an example for subscribable
      # items that have tax data in the invoice items.
      marketplace_line_item = T.must(billing_transaction.line_items.detect { |li| li.description.include?(marketplace_invoice_item.charge_name) })
      assert_equal 1, marketplace_line_item.tax_items.count
      marketplace_tax_item = T.must(marketplace_line_item.tax_items.first)
      zuora_marketplace_tax_item = T.must(marketplace_invoice_item.taxation_items.first)
      assert_equal "Marketplace Tax", marketplace_tax_item.name
      assert_equal zuora_marketplace_tax_item.tax_amount.cents, marketplace_tax_item.amount_in_cents
      assert_equal zuora_marketplace_tax_item.id, marketplace_tax_item.source_id
      assert_equal "zuora", marketplace_tax_item.source_name

      usage_line_item = T.must(billing_transaction.line_items.detect { |li| li.description.include?(usage_invoice_item.charge_name) })
      assert_equal 1, usage_line_item.tax_items.count
      usage_tax_item = T.must(usage_line_item.tax_items.first)
      zuora_usage_tax_item = T.must(usage_invoice_item.taxation_items.first)
      assert_equal "Usage Tax", usage_tax_item.name
      assert_equal zuora_usage_tax_item.tax_amount.cents, usage_tax_item.amount_in_cents
      assert_equal zuora_usage_tax_item.id, usage_tax_item.source_id
      assert_equal "zuora", usage_tax_item.source_name

      # Logs metrics for the total amount of tax and items created
      tags = ["success:true"]
      assert_dogstats_count(3, "billing.billing_transaction.tax_item.diff", tags: tags)
      assert_dogstats_count(3, "billing.billing_transaction.tax_item.created", tags: tags)
      assert_dogstats_count(3, "billing.billing_transaction.tax_item.cream", tags: tags)
    end

    test "does not fail and falls back to the pricing implementation when uuid doesn't have charges" do
      plan = GitHub::Plan.pro
      @user.update!(plan: plan)
      uuid = plan.product_uuid(@user.plan_duration)
      charge = uuid.charges.first
      assert charge, "No charge found for #{uuid.inspect}"

      service_start_date = "2022-09-22"
      service_end_date = "2022-10-21"
      invoice_item = Billing::Zuora::InvoiceItem.new({
        "id" => SecureRandom.alphanumeric(32),
        "subscriptionId" => @plan_subscription.zuora_subscription_id,
        "unitPrice" => charge.price,
        "chargeAmount" => charge.price,
        "chargeId" => SecureRandom.alphanumeric(32),
        "chargeName" => charge.name,
        "unitOfMeasure" =>  "",
        "quantity" => 1,
        "subscriptionName" => @plan_subscription.zuora_subscription_number,
        "productRatePlanChargeId" => charge.zuora_product_rate_plan_charge_id,
        "serviceStartDate" => service_start_date,
        "serviceEndDate" => service_end_date,
      })

      # This simulates UUIDs that haven't been backfilled
      uuid.update!(charges: nil)
      assert_empty uuid.reload.charges

      billing_transaction = Billing::BillingTransaction.new(
        amount_in_cents: charge.price,
        plan_subscription: @plan_subscription,
      )

      assert_difference "Billing::BillingTransaction::LineItem.count", 1 do
        billing_transaction.log_recurring_charge(
          billable_entity: @user,
          invoiced_items: [invoice_item],
          charge_type: "recurring-charge"
        )
      end
      billing_transaction.reload

      line_item = T.must(billing_transaction.line_items.first)
      assert_equal invoice_item.charge_amount.cents, line_item.amount_in_cents
      assert_equal invoice_item.service_start_date, line_item.service_start_date.to_s
      assert_equal invoice_item.service_end_date, line_item.service_end_date.to_s
    end

    test "creates a line item for a GitHub Plan without other recurring line items" do
      plan = GitHub::Plan.pro
      @user.update!(plan: plan)
      uuid = plan.product_uuid(@user.plan_duration)
      charge = uuid.charges.first
      assert charge, "No charge found for #{uuid.inspect}"

      service_start_date = "2022-09-22"
      service_end_date = "2022-10-21"
      invoice_item = Billing::Zuora::InvoiceItem.new({
        "id" => SecureRandom.alphanumeric(32),
        "subscriptionId" => @plan_subscription.zuora_subscription_id,
        "unitPrice" => charge.price,
        "chargeAmount" => charge.price,
        "chargeId" => SecureRandom.alphanumeric(32),
        "chargeName" => charge.name,
        "unitOfMeasure" =>  "",
        "quantity" => 1,
        "subscriptionName" => @plan_subscription.zuora_subscription_number,
        "productRatePlanChargeId" => charge.zuora_product_rate_plan_charge_id,
        "serviceStartDate" => service_start_date,
        "serviceEndDate" => service_end_date,
      })

      billing_transaction = Billing::BillingTransaction.new(
        amount_in_cents: charge.price,
        plan_subscription: @plan_subscription,
      )

      assert_difference "Billing::BillingTransaction::LineItem.count", 1 do
        billing_transaction.log_recurring_charge(
          billable_entity: @user,
          invoiced_items: [invoice_item],
          charge_type: "recurring-charge"
        )
      end
      billing_transaction.reload

      line_item = T.must(billing_transaction.line_items.first)
      assert_equal invoice_item.charge_amount.cents, line_item.amount_in_cents
      assert_equal invoice_item.service_start_date, line_item.service_start_date.to_s
      assert_equal invoice_item.service_end_date, line_item.service_end_date.to_s
      assert_equal invoice_item.charge_name, line_item.description
      assert_equal invoice_item.product_rate_plan_charge_id, line_item.zuora_product_rate_plan_charge_id
    end

    test "creates a new billing transaction with recurring line items for a business billable entity" do
      plan_subscription = create(:billing_plan_subscription, :business_owned)
      customer = plan_subscription.customer
      business = customer.business
      ghas_product_uuid = create(:billing_product_uuid, :advanced_security)
      create(
        :billing_subscription_item,
        plan_subscription: plan_subscription,
        subscribable: ghas_product_uuid,
        quantity: 2,
      )

      business.plan_subscription.reload

      service_start_date = "2022-12-06"
      service_end_date = "2023-01-05"
      quantity = 2
      invoice_items = [
        Billing::Zuora::InvoiceItem.new({
          "serviceEndDate" => service_end_date,
          "serviceStartDate" => service_start_date,
          "subscriptionId" => "8ad08ccf84eab9df0184eb743f8976ac",
          "unitPrice" => ghas_product_uuid.base_price.dollars,
          "id" => "8ad08ccf84eab9df0184eb744152770d",
          "chargeAmount" => ghas_product_uuid.base_price.dollars * quantity,
          "chargeId" => "8ad08ccf84eab9df0184eb743f5076a6",
          "chargeName" => ghas_product_uuid.line_item_description,
          "unitOfMeasure" => "License",
          "quantity" => quantity,
          "subscriptionName" => "A-S00099623",
          "productRatePlanChargeId" => ghas_product_uuid.zuora_product_rate_plan_charge_ids[:unit],
        })
      ]

      billing_transaction = Billing::BillingTransaction.new(
        amount_in_cents: ghas_product_uuid.base_price.cents * quantity,
        plan_subscription: plan_subscription,
      )

      assert_difference "Billing::BillingTransaction::LineItem.count", 1 do
        billing_transaction.log_recurring_charge \
          billable_entity: business,
          invoiced_items: invoice_items,
          charge_type: "prorate-charge"
      end
      billing_transaction.reload
      assert_equal 1, billing_transaction.line_items.count

      assert_equal "prorate-charge", billing_transaction.transaction_type
      assert_equal 1, ghas_product_uuid.reload.billing_transaction_line_items.count

      line_item = billing_transaction.line_items.find_by!(subscribable: ghas_product_uuid)
      assert_equal ghas_product_uuid.base_price.cents * quantity, line_item.amount_in_cents
      assert_equal service_start_date, line_item.service_start_date.to_s
      assert_equal service_end_date, line_item.service_end_date.to_s
      assert_equal ghas_product_uuid.zuora_product_rate_plan_charge_ids[:unit], line_item.zuora_product_rate_plan_charge_id
    end

    test "uses the invoice amount for a matching Marketplace subscription item" do
      plan_subscription = create(:billing_plan_subscription, :zuora)
      user = plan_subscription.user

      approved_listing = create(:marketplace_listing, :verified)
      approved_listing_plan = create(:marketplace_listing_plan, :published, listing: approved_listing)

      create(
        :billing_subscription_item,
        plan_subscription: plan_subscription,
        subscribable: approved_listing_plan,
        quantity: 1,
      )
      user.plan_subscription.reload

      service_start_date = "2022-09-22"
      service_end_date = "2022-10-21"
      zuora_product_rate_plan_charge_id = SecureRandom.hex
      invoiced_items = [
        Billing::Zuora::InvoiceItem.new({
          "id" => "invoice-id",
          "chargeId" => SecureRandom.alphanumeric(32),
          "chargeName" => approved_listing_plan.zuora_product_name,
          "chargeAmount" => 7.89,
          "quantity" => 1.0,
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "productRatePlanChargeId" => zuora_product_rate_plan_charge_id,
        }),
      ]

      billing_transaction = Billing::BillingTransaction.new(
        amount_in_cents: 789,
        plan_subscription: plan_subscription,
      )
      assert_difference "Billing::BillingTransaction::LineItem.count", 1 do
        billing_transaction.log_recurring_charge \
          billable_entity: user,
          invoiced_items: invoiced_items,
          charge_type: "prorate-charge"
      end
      billing_transaction.reload

      assert_equal 1, approved_listing_plan.reload.billing_transaction_line_items.count
      assert_equal 1, billing_transaction.line_items.count
      marketplace_line_item = billing_transaction.line_items.first
      marketplace_line_item = T.must(marketplace_line_item)
      assert_equal 789, marketplace_line_item.amount_in_cents
      assert_equal approved_listing, marketplace_line_item.listing
      assert_equal "prorate-charge", billing_transaction.transaction_type
      assert_equal service_start_date, marketplace_line_item.service_start_date.to_s
      assert_equal service_end_date, marketplace_line_item.service_end_date.to_s
      assert_equal zuora_product_rate_plan_charge_id, marketplace_line_item.zuora_product_rate_plan_charge_id
    end

    test "records the new quantity when combining items for prorated upgrades" do
      plan_subscription = create(:billing_plan_subscription, :zuora)
      user = plan_subscription.user
      listing = create(:marketplace_listing, :verified)
      plan = create(:marketplace_listing_plan, :published, :per_unit, listing: listing)

      create(
        :billing_subscription_item,
        plan_subscription: plan_subscription,
        subscribable: plan,
        quantity: 10,
      )
      copilot_item = create(
        :billing_subscription_item,
        :with_product_uuid,
        plan_subscription: plan_subscription,
        quantity: 1
      )
      copilot = copilot_item.subscribable

      user.plan_subscription.reload

      marketplace_item_charge_id = SecureRandom.alphanumeric(32)
      service_start_date = "2022-09-22"
      service_end_date = "2022-10-21"
      zuora_product_rate_plan_charge_id = SecureRandom.hex
      invoiced_items = [
        Billing::Zuora::SubscribableInvoiceItem.new({
          "chargeId" => marketplace_item_charge_id,
          "unitPrice" => plan.monthly_price_in_cents / 100,
          "chargeName" => plan.zuora_product_name,
          "chargeAmount" => -5.00,
          "quantity" => 5.0,
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "productRatePlanChargeId" => zuora_product_rate_plan_charge_id,
        }, subscribable: plan),
        Billing::Zuora::SubscribableInvoiceItem.new({
          "chargeId" => marketplace_item_charge_id,
          "unitPrice" => plan.monthly_price_in_cents / 100,
          "chargeName" => plan.zuora_product_name,
          "chargeAmount" => 10.00,
          "quantity" => 10.0,
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "productRatePlanChargeId" => zuora_product_rate_plan_charge_id,
        }, subscribable: plan),
        Billing::Zuora::SubscribableInvoiceItem.new({
          "chargeId" => SecureRandom.alphanumeric(32),
          "unitPrice" => copilot.monthly_price_in_cents / 100,
          "chargeName" => copilot.line_item_description,
          "chargeAmount" => 10.00,
          "quantity" => 1.0,
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "productRatePlanChargeId" => copilot.zuora_product_rate_plan_charge_ids.values.first,
        }, subscribable: copilot)
      ]

      billing_transaction = Billing::BillingTransaction.new(
        amount_in_cents: 5_00,
        plan_subscription: plan_subscription,
      )

      # The first line item is for a Marketplace Listing and the second is a Copilot line item
      assert_difference "Billing::BillingTransaction::LineItem.count", 2 do
        billing_transaction.log_recurring_charge \
          billable_entity: user,
          invoiced_items: invoiced_items,
          charge_type: "prorate-charge"
      end
      billing_transaction.reload

      assert_equal 1, plan.reload.billing_transaction_line_items.count
      assert_equal 1, billing_transaction.line_items.marketplace.count
      line_item = billing_transaction.line_items.first
      line_item = T.must(line_item)
      assert_equal plan, line_item.subscribable
      assert_equal 5_00, line_item.amount_in_cents
      assert_equal 10, line_item.quantity
      assert_equal zuora_product_rate_plan_charge_id, line_item.zuora_product_rate_plan_charge_id

      assert_equal 1, copilot.reload.billing_transaction_line_items.count
      assert_equal 1, billing_transaction.line_items.product_uuids.count
      line_item = billing_transaction.line_items.last!
      assert_equal copilot, line_item.subscribable
      assert_equal 10_00, line_item.amount_in_cents
      assert_equal 1, line_item.quantity
      assert_equal copilot.zuora_product_rate_plan_charge_ids.values.first,
        line_item.zuora_product_rate_plan_charge_id

      assert_equal "prorate-charge", billing_transaction.transaction_type
      assert_equal service_start_date, line_item.service_start_date.to_s
      assert_equal service_end_date, line_item.service_end_date.to_s
    end

    test "records extras for copilot for business line item" do
      service_start_date = "2023-02-01"
      service_end_date = "2023-02-28"

      plan_subscription = create(:billing_plan_subscription, :org)
      ghas_product_uuid = create(:billing_product_uuid, :advanced_security)
      copilot_product_uuid = create(:billing_product_uuid, :copilot_business)

      org = plan_subscription.billable_entity

      ghas_subscription_item = create(
        :billing_subscription_item,
        plan_subscription: plan_subscription,
        subscribable: ghas_product_uuid,
        quantity: 1,
      )

      travel_to Date.parse(service_start_date) do
        create_list(:copilot_seat, 3, organization: org) # create 3 seats at beginning of cycle
        create_list(:copilot_seat, 2, organization: org, created_at: 14.days.from_now) # create 2 seats mid-cycle
      end

      invoiced_items = [
        Billing::Zuora::InvoiceItem.new({
          "id" => "invoice-id",
          "unitPrice" => 1,
          "chargeId" => SecureRandom.alphanumeric(32),
          "chargeName" => Billing::BillingTransaction::LineItem::COPILOT_FOR_BUSINESS_USAGE_DESCRIPTION,
          "chargeAmount" => 76.00,
          "quantity" => 4.0,
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "productRatePlanChargeId" => copilot_product_uuid.zuora_product_rate_plan_charge_ids[:unit],
        }),
        Billing::Zuora::SubscribableInvoiceItem.new({
          "id" => "different-invoice-id",
          "unitPrice" => 1,
          "chargeId" => SecureRandom.alphanumeric(32),
          "chargeName" => ghas_product_uuid.line_item_description,
          "chargeAmount" => 2.00,
          "quantity" => 1.0,
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "productRatePlanChargeId" => ghas_product_uuid.zuora_product_rate_plan_charge_ids.first[1],
        }, subscribable: ghas_subscription_item.subscribable),
      ]

      billing_transaction = Billing::BillingTransaction.new(
        amount_in_cents: 78_00,
        plan_subscription: plan_subscription,
      )

      assert_difference "Billing::BillingTransaction::LineItem.count", 2 do
        billing_transaction.log_recurring_charge \
          billable_entity: org,
          invoiced_items: invoiced_items,
          charge_type: "prorate-charge"
      end
      billing_transaction.reload


      copilot_line_item = billing_transaction.line_items.find_by!(description: Billing::BillingTransaction::LineItem::COPILOT_FOR_BUSINESS_USAGE_DESCRIPTION)
      ghas_line_item = billing_transaction.line_items.find_by!(product_uuid: ghas_product_uuid)

      assert copilot_line_item.extras.present?
      refute ghas_line_item.extras.present?

      copilot_extras = copilot_line_item.extras
      assert_equal 3, copilot_extras["seats_billed_in_full"] # 3 seats created on or before the service start date
      assert_equal "19.0", copilot_extras["unit_price"]
      assert_includes copilot_extras["prorations"], { "days" => 14, "count" => 2 } # 2 seats created after mid-month
    end

    test "records extras for enterprise acccount sponsorship line items" do
      sub_item = create(:sponsors_subscription_item, :self_serve_business)
      plan_subscription = sub_item.plan_subscription
      business = plan_subscription.billable_entity
      member_org = sub_item.organization

      other_member_org = create(:organization, business: business)
      other_member_org_sub_item = create(:sponsors_subscription_item,
        account: other_member_org,
        subscribable: sub_item.sponsors_tier
      )

      assert_equal other_member_org.business, member_org.business
      assert_equal other_member_org_sub_item.subscribable, sub_item.subscribable

      invoiced_items = [
        sponsors_invoice_items(
          plan_sub: plan_subscription,
          tier: sub_item.subscribable,
          subscription_item: sub_item,
          fee: 3,
        ),
        # This is an intentional duplicate used to ensure we combine similar line items in the
        # case there's e.g. an upgrade where we have prorated positive and negative invoice items.
        sponsors_invoice_items(
          plan_sub: plan_subscription,
          tier: sub_item.subscribable,
          subscription_item: sub_item,
          fee: -1,
        ),
        sponsors_invoice_items(
          plan_sub: plan_subscription,
          tier: other_member_org_sub_item.subscribable,
          subscription_item: other_member_org_sub_item,
          fee: 1,
        ),
      ].flatten

      billing_transaction = Billing::BillingTransaction.new(
        amount_in_cents: invoiced_items.sum { |item| item.charge_amount.cents },
        plan_subscription: plan_subscription,
      )

      # two sponsorship line items, and two sponsorship fee line items
      assert_difference "Billing::BillingTransaction::LineItem.sponsorships.count", 4 do
        billing_transaction.log_recurring_charge \
          billable_entity: business,
          invoiced_items: invoiced_items,
          charge_type: "recurring-charge"
      end
      billing_transaction.reload

      # tracking fees and charges for both org's subscriptions
      fee_line_items, charge_line_items = billing_transaction.line_items.partition(&:sponsors_fee?)
      [fee_line_items, charge_line_items].each do |line_items|
        assert_same_elements(
          [member_org.id, other_member_org.id],
          line_items.map { |item| item.extras["managing_entity_id"] }
        )
      end
    end

    test "filters usage line items by product rate plan charge id" do
      service_start_date = "2023-02-01"
      service_end_date = "2023-02-28"

      plan_subscription = create(:billing_plan_subscription, :org)
      copilot_product_uuid = create(:billing_product_uuid, :copilot_business)

      org = plan_subscription.billable_entity

      invoiced_items = [
        Billing::Zuora::InvoiceItem.new({
          "id" => "invoice-id-1",
          "unitPrice" => 1,
          "chargeId" => SecureRandom.alphanumeric(32),
          "chargeName" => Billing::BillingTransaction::LineItem::COPILOT_FOR_BUSINESS_USAGE_DESCRIPTION,
          "chargeAmount" => 76.00,
          "quantity" => 4.0,
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "productRatePlanChargeId" => copilot_product_uuid.zuora_product_rate_plan_charge_ids[:unit],
        }),
        Billing::Zuora::InvoiceItem.new({
          "id" => "invoice-id-2",
          "unitPrice" => 1,
          "chargeId" => SecureRandom.alphanumeric(32),
          "chargeName" => "Not the right description",
          "chargeAmount" => 76.00,
          "quantity" => 4.0,
          "serviceStartDate" => service_start_date,
          "serviceEndDate" => service_end_date,
          "productRatePlanChargeId" => copilot_product_uuid.zuora_product_rate_plan_charge_ids[:unit],
        })
      ]

      billing_transaction = Billing::BillingTransaction.new(
        amount_in_cents: 78_00,
        plan_subscription: plan_subscription,
      )

      # Both invoice items should be turned into line items
      assert_difference "Billing::BillingTransaction::LineItem.count", 2 do
        billing_transaction.log_recurring_charge \
          billable_entity: org,
          invoiced_items: invoiced_items,
          charge_type: "prorate-charge"
      end
    end

    test "does not record extras for sponsorship line items when no managing entity discrepancy exists" do
      sub_item = create(:sponsors_subscription_item)
      plan_subscription = sub_item.plan_subscription

      invoiced_items = sponsors_invoice_items(
        plan_sub: plan_subscription,
        tier: sub_item.subscribable,
        subscription_item: sub_item,
        fee: 0,
      )

      billing_transaction = Billing::BillingTransaction.new(
        amount_in_cents: invoiced_items.sum { |item| item.charge_amount.cents },
        plan_subscription: plan_subscription,
      )

      # single sponsorship line item (since no fee charged)
      assert_difference "Billing::BillingTransaction::LineItem.count", 1 do
        billing_transaction.log_recurring_charge \
          billable_entity: plan_subscription.user,
          invoiced_items: invoiced_items,
          charge_type: "recurring-charge"
      end
      billing_transaction.reload

      assert_nil(
        T.must(billing_transaction.line_items.first).extras,
        "no extra info should be included since ownership is unambiguous"
      )
    end
  end

  test "requires transaction_id if status is present" do
    attrs = {
      user: @user,
      plan_subscription: @plan_subscription,
      amount_in_cents: 100,
      transaction_type: "signed-up",
      payment_type: :credit_card,
      renewal_frequency: :monthly,
      platform: :zuora,
    }

    billing_transaction = Billing::BillingTransaction.new(attrs)
    assert billing_transaction.valid?, billing_transaction.errors.full_messages.join(",")

    billing_transaction = Billing::BillingTransaction.new \
      attrs.merge(last_status: :settled)
    refute billing_transaction.valid?, billing_transaction.errors.full_messages.join(",")

    billing_transaction = Billing::BillingTransaction.new \
      attrs.merge(last_status: :settled, transaction_id: "abc123")
    assert billing_transaction.valid?, billing_transaction.errors.full_messages.join(",")
  end

  test "does not require transaction_id if status is failed" do
    billing_transaction = Billing::BillingTransaction.new(
      user: @user,
      plan_subscription: @plan_subscription,
      amount_in_cents: 100,
      transaction_type: "signed-up",
      payment_type: :credit_card,
      renewal_frequency: :monthly,
      platform: :zuora,
      last_status: :failed,
      transaction_id: nil,
    )
    assert billing_transaction.valid?, billing_transaction.errors.full_messages.join(",")
  end

  test "does not require transaction_id if status is processor_declined" do
    billing_transaction = Billing::BillingTransaction.new(
      user: @user,
      plan_subscription: @plan_subscription,
      amount_in_cents: 100,
      transaction_type: "signed-up",
      payment_type: :credit_card,
      renewal_frequency: :monthly,
      platform: :zuora,
      last_status: :processor_declined,
      transaction_id: nil,
    )
    assert billing_transaction.valid?, billing_transaction.errors.full_messages.join(",")
  end

  test "does not require transaction_id if status is authorized" do
    billing_transaction = Billing::BillingTransaction.new(
      user: @user,
      plan_subscription: @plan_subscription,
      amount_in_cents: 100,
      transaction_type: "signed-up",
      payment_type: :credit_card,
      renewal_frequency: :monthly,
      platform: :zuora,
      last_status: :authorized,
      transaction_id: nil,
    )
    assert billing_transaction.valid?, billing_transaction.errors.full_messages.join(",")
  end

  test "generates a transaction id based on our id" do
    int = @transaction.id
    assert_equal "0-#{int.to_s(36).rjust(6, "0")}", @transaction.our_transaction_id
  end

  test ".log should gather data from user and plan" do
    Timecop.freeze(Time.zone.local(2020, 5, 1, 12)) do
      pro_plan = GitHub::Plan.find("pro")
      now = GitHub::Billing.now
      months = 3.months

      three_months_ago = GitHub::Billing.now - 3.months
      paying_user      = create :paypal_user,
        login: "mrmoney",
        created_at: three_months_ago,
        email: "mrmoney@mrmoneyenterprises.com",
        plan: pro_plan,
        plan_duration: "month",
        seats: 50,
        plan_subscription: create(:billing_plan_subscription)

      assert_difference "Billing::BillingTransaction.count", +1 do
        Billing::BillingTransaction.log user: paying_user,
          plan_subscription: paying_user.plan_subscription,
          amount_in_cents: pro_plan.cost_in_cents,
          transaction_type: "recurring-charge",
          transaction: successful_credit_card_transaction
      end

      logged_transaction = Billing::BillingTransaction.last
      logged_transaction = T.must(logged_transaction)
      assert_equal "mrmoney", logged_transaction.user_login
      assert_equal three_months_ago.utc.to_s, T.must(logged_transaction.user_created_at).utc.to_s
      assert_equal "mrmoney@mrmoneyenterprises.com", logged_transaction.billing_email_address
      assert_equal "user", logged_transaction.user_type
      assert_equal pro_plan.name, logged_transaction.plan_name
      assert_equal pro_plan.cost_in_cents, logged_transaction.plan_price_in_cents
      assert_equal 50, logged_transaction.seats_total
      assert  logged_transaction.monthly?

      # from payment_method
      assert_equal "California", logged_transaction.region
      assert_equal "12345", logged_transaction.postal_code
      assert_equal "USA", logged_transaction.country
    end
  end

  test ".log gathers data from a credit card transaction" do
    assert_difference "Billing::BillingTransaction.count", +1 do
      Billing::BillingTransaction.log user: @user,
        plan_subscription: @plan_subscription,
        amount_in_cents: 10_00,
        transaction_type: "recurring-charge",
        transaction: successful_credit_card_transaction
    end

    logged_transaction = Billing::BillingTransaction.last
    logged_transaction = T.must(logged_transaction)
    assert logged_transaction.credit_card?
    assert_equal @plan_subscription, logged_transaction.plan_subscription
    assert_equal "jgdxs6", logged_transaction.transaction_id
    assert_equal 411111, logged_transaction.bank_identification_number
    assert_equal "Unknown", logged_transaction.country_of_issuance
    assert_equal "1111", logged_transaction.last_four
    assert logged_transaction.settled?
  end

  test ".log gathers data from a paypal transaction" do
    user = create :paypal_user, plan_subscription: create(:billing_plan_subscription)

    assert_difference "Billing::BillingTransaction.count", +1 do
      Billing::BillingTransaction.log user: user,
        amount_in_cents: 22_00,
        plan_subscription: user.plan_subscription,
        transaction_type: "recurring-charge",
        transaction: successful_paypal_transaction
    end

    logged_transaction = Billing::BillingTransaction.last
    logged_transaction = T.must(logged_transaction)
    assert logged_transaction.paypal?
    assert_equal "fr6sgr", logged_transaction.transaction_id
    assert_equal "payer@example.com", logged_transaction.paypal_email
    assert logged_transaction.settled?

    assert_nil logged_transaction.bank_identification_number
    assert_nil logged_transaction.country_of_issuance
    assert_nil logged_transaction.last_four
  end

  test ".log should gather data from organization with yearly plan" do
    three_months_ago = GitHub::Billing.now - 3.months
    one_week_ago     = GitHub::Billing.now - 1.week

    create :user, login: "mrmoney",
      created_at: three_months_ago,
      email: "mrmoney@mrmoneyenterprises.com",
      plan: "free",
      plan_duration: "month"

    silver_org = create :credit_card_org, admin: @user,
      billing_email: "billing_department@mrmoneyenterprises.com",
      created_at: one_week_ago,
      login: "MrMoneyEnterprises",
      plan: "silver",
      plan_duration: "year",
      plan_subscription: create(:billing_plan_subscription)

    assert_difference "Billing::BillingTransaction.count", +1 do
      Billing::BillingTransaction.log user: silver_org,
        plan_subscription: silver_org.plan_subscription,
        amount_in_cents: 5000,
        transaction_id: 12345,
        transaction_type: "recurring-charge"
    end

    logged_transaction = Billing::BillingTransaction.last
    logged_transaction = T.must(logged_transaction)
    assert_equal "MrMoneyEnterprises", logged_transaction.user_login
    assert_equal one_week_ago.utc.to_s, T.must(logged_transaction.user_created_at).utc.to_s
    assert_equal "billing_department@mrmoneyenterprises.com", logged_transaction.billing_email_address
    assert_equal "organization", logged_transaction.user_type

    assert_equal "silver", logged_transaction.plan_name
    assert_equal 5000, logged_transaction.plan_price_in_cents
    assert logged_transaction.yearly?
  end

  test ".log should gather data from user with coupon" do
    pro_plan = GitHub::Plan.find("pro")
    coupon           = create :coupon, discount: 0.25, code: "HACKSALOT"

    paying_user = create :credit_card_user, login: "mrmoney",
      plan: pro_plan,
      plan_subscription: create(:billing_plan_subscription),
      coupon: "HACKSALOT"

    logged_transaction = T.let(nil, T.nilable(Billing::BillingTransaction))

    assert_difference "Billing::BillingTransaction.count", +1 do
      logged_transaction = Billing::BillingTransaction.log \
        user: paying_user,
        plan_subscription: paying_user.plan_subscription,
        plan_name: paying_user.plan.name,
        amount_in_cents: 900,
        transaction_id: 12345,
        transaction_type: "recurring-charge"
    end
    logged_transaction = T.must(logged_transaction)

    assert_equal "mrmoney", logged_transaction.user_login

    assert_equal "pro", logged_transaction.plan_name
    assert_equal pro_plan.cost_in_cents, logged_transaction.plan_price_in_cents
    assert_equal 900, logged_transaction.amount_in_cents

    assert_equal "HACKSALOT", logged_transaction.coupon_name
    assert_equal pro_plan.cost_in_cents * coupon.discount, logged_transaction.discount_in_cents
  end

  test ".log works with attempted transactions" do
    logged_transaction = T.let(nil, T.nilable(Billing::BillingTransaction))
    assert_difference "Billing::BillingTransaction.count", +1 do
      logged_transaction = Billing::BillingTransaction.log \
        user: @user,
        plan_subscription: @plan_subscription,
        amount_in_cents: 900,
        transaction_type: "recurring-charge"
    end
    refute_nil logged_transaction
  end

  test "can .log multiple attempts" do
    2.times do
      logged_transaction = Billing::BillingTransaction.log \
        user: @user,
        plan_subscription: @plan_subscription,
        amount_in_cents: 900,
        transaction_type: "recurring-charge"
      refute_nil logged_transaction
    end
  end

  test "#pending_status_updates updates transactions in a non-final state" do
    create :billing_transaction, transaction_id: "jgdxs6",
      amount_in_cents: 1200,
      transaction_type: "signed-up",
      user: @user,
      payment_type: :credit_card,
      renewal_frequency: :monthly,
      platform: :zuora,
      transaction: successful_credit_card_transaction

    assert_difference "Billing::BillingTransactionStatus.count", 0 do
      Billing::BillingTransaction.update_transactions_with_pending_status
    end

    logged_transaction = Billing::BillingTransaction.last
    assert T.must(logged_transaction).settled?
    assert_equal "2012-04-27_Github", T.must(logged_transaction).settlement_batch_id
  end

  test "#update_status_from_processor ignores transactions with nil transaction_ids" do
    transaction = create :billing_transaction,
      amount_in_cents: 1200,
      transaction_type: "recurring-charge",
      last_status: :submitted_for_settlement,
      user: @user
    transaction.update_attribute(:transaction_id, nil)

    UpdateBillingTransactionStatusJob.expects(:perform_later).with(transaction).never

    Billing::BillingTransaction.update_transactions_with_pending_status
  end

  test "#update_status_from_processor finds Zuora Braintree transactions" do
    braintree_transaction_id = "5g8s00r2"
    zuora_transaction_id = "2c92c0fa62942c5e0162968aeb0140cc"
    transaction = create(:billing_transaction,
      transaction_id: braintree_transaction_id,
      last_status: :authorized,
      platform: :zuora,
      platform_transaction_id: zuora_transaction_id)

    UpdateBillingTransactionStatusJob.expects(:perform_later).with(transaction)

    Billing::BillingTransaction.update_transactions_with_pending_status
  end

  context "#plan_subscription" do
    test "returns the plan subscription recorded on the transaction" do
      plan_subscription = create(:billing_plan_subscription)
      transaction = build(:billing_transaction, plan_subscription: plan_subscription)
      assert_equal plan_subscription, transaction.plan_subscription
    end

    test "returns the transaction's user's plan subscription if no plan subscription is recorded on the transaction" do
      plan_subscription = create(:billing_plan_subscription)
      transaction = build(:billing_transaction, user: plan_subscription.user, plan_subscription: nil)
      assert_equal plan_subscription, transaction.plan_subscription
    end
  end

  context "update with braintree_transaction" do
    test "populates from a raw braintree transaction" do
      transaction = create :billing_transaction, transaction_id: "jgdxs6",
        amount_in_cents: 1200,
        transaction_type: "signed-up",
        user: @user

      transaction.update(transaction: successful_credit_card_transaction)

      refute transaction.changed?
      assert_equal "jgdxs6", transaction.transaction_id
      assert transaction.settled?
    end

    test "handles nils" do
      transaction = create :billing_transaction
      refute transaction.transaction = nil
      refute transaction.changed?
    end
  end

  test "has_many association and class_name option are working correctly" do
    billing_transaction = create :billing_transaction
    status = billing_transaction.statuses.build
    assert_equal [status], billing_transaction.statuses
  end

  test "date is in billing timezone" do
    bt = Billing::BillingTransaction.new(created_at: Time.utc(2014, 8, 7, 0, 1))
    assert_equal Date.new(2014, 8, 6), bt.date
  end

  test "defaults to dotcom product" do
    bt = create :billing_transaction
    assert_equal "dotcom", bt.product
  end

  test "disallows invalid product" do
    refute build(:billing_transaction, product: "other").valid?
  end

  test "billing transaction still exists even if the user is destroyed" do
    transaction = create(:billing_transaction)
    transaction.live_user.destroy
    transaction.reload
    assert transaction
  end

  test "billing transaction still exists even if the customer is destroyed" do
    customer = create(:customer)
    transaction = create(:billing_transaction, customer: customer)
    customer.destroy

    transaction.reload
    assert transaction
  end

  test "billing transaction still exists even if the business is destroyed" do
    transaction = create(:billing_transaction, :business_owned)
    assert transaction.billable_business?
    transaction.billable_entity.destroy

    transaction.reload
    assert transaction
  end

  context "#chargeback!" do
    test "creates an associated status, note, and sets last status" do
      transaction = create :billing_transaction
      reason_for_chargeback = "REASON"
      amount = "55"
      charged_back_status_enum = "charged_back"
      received_date = GitHub::Billing.now

      mock_braintree_dispute = Braintree::Dispute.send(
        :new,
        received_date: received_date.to_date.to_s,
        reason: reason_for_chargeback,
        amount: amount,
      )

      transaction.chargeback!(mock_braintree_dispute)
      last_status_record = transaction.statuses.last
      note = transaction.notes.last

      note_details = "Chargeback\n" \
        "Date received: #{received_date.to_date}\n" \
        "Reason: #{reason_for_chargeback}"

      assert_equal last_status_record.amount_in_cents, amount.to_i * 100
      assert_equal note.note, note_details
      assert_equal transaction.last_status, charged_back_status_enum
    end
  end

  context "#is_refund?" do
    test "true when transaction has an associated sell transaction" do
      transaction = create(:billing_transaction, sale_transaction_id: "abc123")

      assert transaction.is_refund?, "Transaction should be a refund"
    end

    test "false when sale transaction is blank" do
      nil_id = create(:billing_transaction, sale_transaction_id: nil)
      blank_id = create(:billing_transaction, sale_transaction_id: "")

      refute nil_id.is_refund?, "Transaction should not be a refund"
      refute blank_id.is_refund?, "Transaction should not be a refund"
    end
  end

  context "is_within_a_year_ago" do
    test "false when transaction is more than a year old" do
      transaction = create(:billing_transaction, sale_transaction_id: "abc123")
      transaction.update_attribute(:created_at, 2.years.ago)
      assert_equal false, transaction.is_within_a_year_ago?
    end

    test "true when transaction created now" do
      transaction = create(:billing_transaction, sale_transaction_id: "abc123")
      assert_equal true, transaction.is_within_a_year_ago?
    end
  end


  context "#platform_url" do
    test "is a Braintree URL for Braintree transactions" do
      transaction = Billing::BillingTransaction.new(
        platform: :braintree,
        platform_transaction_id: "zebras",
        transaction_id: "lions",
      )

      assert_match %r(braintreegateway.com/merchants/\w+/transactions/zebras), transaction.platform_url
    end

    test "is a Zuora URL for Zuora Payment transactions" do
      transaction = Billing::BillingTransaction.new(
        platform: :zuora,
        platform_transaction_id: "zebras",
        transaction_id: "lions",
      )

      assert_match %r(zuora.com/apps/NewPayment.do\?method=view&id=zebras), transaction.platform_url
    end

    test "is a Zuora URL for Zuora Credit Balance transactions" do
      transaction = build(:billing_transaction,
        :credit_balance_adjustment,
        platform: :zuora,
        platform_transaction_id: "zebras",
      )

      assert_match %r(zuora.com/apps/CreditBalanceAdjustment.do\?method=view&id=zebras), transaction.platform_url
    end
  end

  context "#platform_name" do
    test "is Braintree for Braintree transactions" do
      transaction = Billing::BillingTransaction.new(
        platform: :braintree,
        platform_transaction_id: "zebras",
        transaction_id: "lions",
      )

      assert_match "Braintree", transaction.platform_name
    end

    test "is Zuora for Zuora transactions" do
      transaction = Billing::BillingTransaction.new(
        platform: :zuora,
        platform_transaction_id: "zebras",
        transaction_id: "lions",
      )

      assert_match "Zuora", transaction.platform_name
    end
  end

  context "#failed?" do
    test "returns true when last_status is failed" do
      @transaction.last_status = :failed
      assert @transaction.failed?
    end

    test "returns true when last_status is not a Billing::BillingTransactionStatuses::SUCCESS status" do
      @transaction.last_status = :voided
      assert @transaction.failed?
    end

    test "returns false when last_status is a Billing::BillingTransactionStatuses::SUCCESS status" do
      @transaction.last_status = :settled
      refute @transaction.failed?
    end
  end

  context "#refund!" do
    test "sends an email" do
      amount_in_cents = 123
      refund_transaction = create(:billing_transaction, :refund, amount_in_cents: amount_in_cents, sale: @transaction)

      mailer = BillingNotificationsMailer.refund(
        @transaction.live_user,
        @transaction.created_at.to_date,
        amount_in_cents,
        "credit card",
        Time.now,
        nil,
        refund_transaction: refund_transaction,
      )

      BillingNotificationsMailer
        .expects(:refund)
        .with(
          @transaction.live_user,
          @transaction.created_at.to_date,
          amount_in_cents,
          "credit card",
          instance_of(ActiveSupport::TimeWithZone),
          nil,
          refund_transaction: refund_transaction,
        )
        .returns(mailer)

      Billing::Refund
        .any_instance
        .stubs(:process)
        .returns(GitHub::Billing::Result.success(refund_transaction))

      @transaction.refund!(amount_in_cents)
    end

    test "sends an email with a custom refund message" do
      amount_in_cents = 123
      refund_transaction = create(:billing_transaction, :refund, amount_in_cents: amount_in_cents, sale: @transaction)
      custom_text = "We did not mean to take your money."

      mailer = BillingNotificationsMailer.refund(
        @transaction.live_user,
        @transaction.created_at.to_date,
        amount_in_cents,
        "credit card",
        Time.now,
        custom_text,
        refund_transaction: refund_transaction,
      )

      BillingNotificationsMailer.expects(:refund).with(
        @transaction.live_user,
        @transaction.created_at.to_date,
        amount_in_cents,
        "credit card",
        instance_of(ActiveSupport::TimeWithZone),
        custom_text,
        refund_transaction: refund_transaction,
      ).returns(mailer)

      Billing::Refund
        .any_instance
        .stubs(:process)
        .returns(GitHub::Billing::Result.success(refund_transaction))

      @transaction.refund!(amount_in_cents, skip_email: false, email_refund_custom_text: custom_text)
    end

    test "does not send an email when skip_email is true" do
      amount_in_cents = 123

      Billing::Refund
        .any_instance
        .stubs(:process)
        .returns(GitHub::Billing::Result.success)

      BillingNotificationsMailer
        .expects(:refund)
        .never

      @transaction.refund!(amount_in_cents, skip_email: true)
    end

    test "caches the refunded billing transaction in the key-value store for 15 minutes" do
      transaction = create(:billing_transaction)
      amount_in_cents = 123
      refund_transaction = create(:billing_transaction, :refund, amount_in_cents: amount_in_cents, sale: transaction)

      Billing::Refund
        .any_instance
        .stubs(:process)
        .returns(GitHub::Billing::Result.success(refund_transaction))

      transaction.refund!(amount_in_cents)

      assert_equal transaction, Billing::BillingTransaction.recent_refunded_transaction(transaction.live_user)

      travel_to Time.now + 15.minutes do
        assert_nil Billing::BillingTransaction.recent_refunded_transaction(transaction.live_user)
      end
    end
  end
end
