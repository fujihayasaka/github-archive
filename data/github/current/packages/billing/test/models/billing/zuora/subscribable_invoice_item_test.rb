# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::SubscribableInvoiceItemTest < GitHub::BillingTestCase
  fixtures do
    @sponsors_tier = create(:sponsors_tier)
    @marketplace_listing_plan = create(:marketplace_listing_plan)
    @sub_item = create(:billing_subscription_item)
  end

  context "#==" do
    test "equal if same raw Zuora response and subscribable and subscription_item" do
      item1 = Billing::Zuora::SubscribableInvoiceItem.new({}, subscription_item: @sub_item)
      item2 = Billing::Zuora::SubscribableInvoiceItem.new({}, subscription_item: @sub_item)

      assert_equal item1, item2
    end

    test "unequal if compared to Billing::Zuora::InvoiceItem" do
      item1 = Billing::Zuora::SubscribableInvoiceItem.new({})
      item2 = Billing::Zuora::InvoiceItem.new({})

      refute_equal item1, item2, "expected to be unequal since different class"
    end

    test "unequal if different raw Zuora response" do
      item1 = Billing::Zuora::SubscribableInvoiceItem.new({ "foo" => "bar" }, subscription_item: @sub_item)
      item2 = Billing::Zuora::SubscribableInvoiceItem.new({ "baz" => "qux" }, subscription_item: @sub_item)

      refute_equal item1, item2, "expected to be unequal since different raw Zuora response"
    end

    test "unequal if different subscribable" do
      item1 = Billing::Zuora::SubscribableInvoiceItem.new({}, subscribable: @marketplace_listing_plan)
      item2 = Billing::Zuora::SubscribableInvoiceItem.new({}, subscribable: @sponsors_tier)

      refute_equal item1, item2, "expected to be unequal since invoice items track different subscribables"
    end

    test "unequal if different subscription items" do
      sub_item2 = create(:sponsors_subscription_item)
      item1 = Billing::Zuora::SubscribableInvoiceItem.new({}, subscription_item: @sub_item)
      item2 = Billing::Zuora::SubscribableInvoiceItem.new({}, subscription_item: sub_item2)

      refute_equal item1, item2, "expected to be unequal due to different subscription_items"
    end

    test "unequal if same subscribable but missing subscription item" do
      item1 = Billing::Zuora::SubscribableInvoiceItem.new({}, subscription_item: @sub_item)
      item2 = Billing::Zuora::SubscribableInvoiceItem.new({}, subscribable: @sub_item.subscribable)

      refute_equal item1, item2, "expected to be unequal since one invoice item doesn't track the subscription item"
    end
  end

  context "#subscribable?" do
    test "returns true" do
      invoice_item = Billing::Zuora::SubscribableInvoiceItem.new({}, subscribable: @marketplace_listing_plan)
      assert_predicate invoice_item, :subscribable?
    end
  end

  context "#subscribable" do
    test "prefers subscribable from the subscription item if present" do
      invoice_item = Billing::Zuora::SubscribableInvoiceItem.new({},
        subscribable: @sponsors_tier,
        subscription_item: @sub_item
      )

      refute_equal @sub_item.subscribable, @sponsors_tier
      assert_equal @sub_item.subscribable, invoice_item.subscribable
    end

    test "uses the subscribable when no subscription item is passed" do
      invoice_item = Billing::Zuora::SubscribableInvoiceItem.new({},
        subscribable: @sponsors_tier,
      )

      assert_equal @sponsors_tier, invoice_item.subscribable
    end
  end

  context "#subscription_item" do
    test "returns passed subscription item" do
      invoice_item = Billing::Zuora::SubscribableInvoiceItem.new({},
        subscribable: @sub_item.subscribable,
        subscription_item: @sub_item
      )

      assert_equal @sub_item, invoice_item.subscription_item
    end
  end

  context "#managing_entity" do
    test "returns the managing organization if present" do
      sponsors_enterprise_sub_item = create(:sponsors_subscription_item, :self_serve_business)
      invoice_item = Billing::Zuora::SubscribableInvoiceItem.new({},
        subscription_item: sponsors_enterprise_sub_item
      )

      assert_equal sponsors_enterprise_sub_item.organization, invoice_item.managing_entity
    end

    test "returns the billable entity if no managing organization" do
      invoice_item = Billing::Zuora::SubscribableInvoiceItem.new({},
        subscription_item: @sub_item
      )

      assert_equal @sub_item.account, invoice_item.managing_entity
    end
  end

  context "#line_item_extras" do
    test "returns managing entity when it differs from the billable entity" do
      sponsors_enterprise_sub_item = create(:sponsors_subscription_item, :self_serve_business)
      invoice_item = Billing::Zuora::SubscribableInvoiceItem.new({},
        subscription_item: sponsors_enterprise_sub_item
      )

      refute_equal sponsors_enterprise_sub_item.account, invoice_item.managing_entity

      expected_hash = { "managing_entity_id" => sponsors_enterprise_sub_item.organization_id }
      assert_equal expected_hash, invoice_item.line_item_extras
    end

    test "returns nil when managing entity is the billable entity" do
      invoice_item = Billing::Zuora::SubscribableInvoiceItem.new({},
        subscription_item: @sub_item
      )

      assert_equal @sub_item.account, invoice_item.managing_entity

      assert_nil invoice_item.line_item_extras
    end

    test "returns nil when missing subscription item" do
      invoice_item = Billing::Zuora::SubscribableInvoiceItem.new({},
        subscribable: @sponsors_tier,
      )

      assert_nil invoice_item.line_item_extras
    end
  end

  context "#sponsors_item?" do
    test "returns true for Sponsors tier subscribable" do
      invoice_item = Billing::Zuora::SubscribableInvoiceItem.new({}, subscribable: @sponsors_tier)
      assert_predicate invoice_item, :sponsors_item?
    end

    test "returns false for Marketplace listing plan subscribable" do
      invoice_item = Billing::Zuora::SubscribableInvoiceItem.new({}, subscribable: @marketplace_listing_plan)
      refute_predicate invoice_item, :sponsors_item?
    end
  end

  context "#sponsors_fee_charge?" do
    test "returns false for Marketplace listing plan subscribable" do
      invoice_item = Billing::Zuora::SubscribableInvoiceItem.new({}, subscribable: @marketplace_listing_plan)
      refute_predicate invoice_item, :sponsors_fee_charge?
    end

    test "returns false for Sponsors tier subscribable when the charge name doesn't include FEE_CHARGE_SUFFIX" do
      charge_name = "sponsors-user-123: Recurring monthly"
      refute_includes charge_name, SponsorsListing::ZuoraDependency::FEE_CHARGE_SUFFIX
      invoice_item = Billing::Zuora::SubscribableInvoiceItem.new({ "chargeName" => charge_name },
        subscribable: @sponsors_tier)
      refute_predicate invoice_item, :sponsors_fee_charge?
    end

    test "returns true for Sponsors tier subscribable when the charge name ends in FEE_CHARGE_SUFFIX" do
      charge_name = "sponsors-user-123: Recurring monthly#{SponsorsListing::ZuoraDependency::FEE_CHARGE_SUFFIX}"
      invoice_item = Billing::Zuora::SubscribableInvoiceItem.new({ "chargeName" => charge_name },
        subscribable: @sponsors_tier)
      assert_predicate invoice_item, :sponsors_fee_charge?
    end

    test "returns false for Sponsors tier subscribable when the charge name includes FEE_CHARGE_SUFFIX somewhere not at the end" do
      charge_name = "sponsors-user-123:#{SponsorsListing::ZuoraDependency::FEE_CHARGE_SUFFIX} Recurring monthly"
      invoice_item = Billing::Zuora::SubscribableInvoiceItem.new({ "chargeName" => charge_name },
        subscribable: @sponsors_tier)
      refute_predicate invoice_item, :sponsors_fee_charge?
    end
  end
end
