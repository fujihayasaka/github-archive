# typed: true
# frozen_string_literal: true

require "test_helper"

class BillingTransactionLineItemTest < GitHub::BillingTestCase
  include GitHub::ZuoraTestHelper

  fixtures do
    @marketplace_listing_plan = create(:marketplace_listing_plan, :published)
    @sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing)
    @product_uuid = create(:billing_product_uuid)
    @copilot_product_uuid = create(:billing_product_uuid, :copilot)

    @transaction = create :billing_transaction
    @transaction.statuses.create amount_in_cents: 1200, status: :authorized

    @marketplace_plan_item = create(:billing_transaction_line_item,
      billing_transaction: @transaction, subscribable: @marketplace_listing_plan)
    @sponsors_tier_item = create(:billing_transaction_line_item,
      billing_transaction: @transaction, subscribable: @sponsors_tier)
    @product_uuid_item = create(:billing_transaction_line_item,
      billing_transaction: @transaction, subscribable: @product_uuid)
    @copilot_item = create(:billing_transaction_line_item,
      billing_transaction: @transaction, subscribable: @copilot_product_uuid)
    @non_subscribable_item = create(:billing_transaction_line_item,
      billing_transaction: @transaction, subscribable: nil)
  end

  context "#total_amount" do
    test "returns the line item's total amount including taxes" do
      line_item = create(:billing_transaction_line_item, amount_in_cents: 100)
      create(:billing_transaction_tax_item, line_item: line_item, amount_in_cents: 10)
      assert_equal Billing::Money.new(110), line_item.total_amount
    end
  end

  context "#tax_amount" do
    test "returns the line item's total tax amount" do
      line_item = create(:billing_transaction_line_item, amount_in_cents: 100)
      create(:billing_transaction_tax_item, line_item: line_item, amount_in_cents: 10)
      create(:billing_transaction_tax_item, line_item: line_item, amount_in_cents: 20)

      assert_equal Billing::Money.new(30), line_item.tax_amount
    end
  end

  context "#receipt_text" do
    test "removes sponsors prefix from line item description" do
      description = "sponsors-maintainerFoo - $5 a month"
      description_without_prefix = "maintainerFoo - $5 a month"
      line_item = Billing::BillingTransaction::LineItem.new(description: description, amount_in_cents: 5_00)
      assert_equal description_without_prefix, line_item.receipt_text
    end

    test "leaves line item description alone when it doesn't include the sponsors prefix" do
      description = "maintainerFoo - $5 a month"
      line_item = Billing::BillingTransaction::LineItem.new(description: description, amount_in_cents: 5_00)
      assert_equal description, line_item.receipt_text
    end

    test "returns line item description when it includes the line amount dollar value already" do
      description = "sponsors-maintainerFoo - $5 a month"
      description_without_prefix = "maintainerFoo - $5 a month"
      line_item = Billing::BillingTransaction::LineItem.new(description: description, amount_in_cents: 5_00)
      assert_equal description_without_prefix, line_item.receipt_text
    end

    test "returns line item description with amount appended when it didn't include the line amount dollar value already" do
      description = "sponsors-maintainerFoo - $5 a month"
      description_without_prefix = "maintainerFoo - $5 a month"
      line_item = Billing::BillingTransaction::LineItem.new(description: description, amount_in_cents: 1_23)
      assert_equal "#{description_without_prefix} ($1.23)", line_item.receipt_text
    end

    test "returns line item description with amount appended when amount is a subset of dollar value in description already" do
      description = "sponsors-maintainerFoo - $500 a month"
      description_without_prefix = "maintainerFoo - $500 a month"
      line_item = Billing::BillingTransaction::LineItem.new(description: description, amount_in_cents: 5_00)
      assert_equal "#{description_without_prefix} ($5.00)", line_item.receipt_text
    end
  end

  context "transaction_created_at_or_after scope" do
    test "returns only line items whose billing transactions were created on or after the given time" do
      three_day_xact = travel_to(3.days.ago) { create(:billing_transaction) }
      three_day_line_item = create(:billing_transaction_line_item, billing_transaction: three_day_xact)
      week_xact = travel_to(1.week.ago) { create(:billing_transaction) }
      week_line_item = create(:billing_transaction_line_item, billing_transaction: week_xact)
      day_xact = travel_to(1.day.ago) { create(:billing_transaction) }
      day_line_item = create(:billing_transaction_line_item, billing_transaction: day_xact)

      result = Billing::BillingTransaction::LineItem.transaction_created_at_or_after(three_day_xact.created_at)
        .where(id: [three_day_line_item, week_line_item, day_line_item])

      assert_includes result, day_line_item
      assert_includes result, three_day_line_item
      refute_includes result, week_line_item
    end
  end

  context "transaction_created_before scope" do
    test "returns only billing transactions created before the given time" do
      three_day_xact = travel_to(3.days.ago) { create(:billing_transaction) }
      three_day_line_item = create(:billing_transaction_line_item, billing_transaction: three_day_xact)
      week_xact = travel_to(1.week.ago) { create(:billing_transaction) }
      week_line_item = create(:billing_transaction_line_item, billing_transaction: week_xact)
      day_xact = travel_to(1.day.ago) { create(:billing_transaction) }
      day_line_item = create(:billing_transaction_line_item, billing_transaction: day_xact)

      result = Billing::BillingTransaction::LineItem.transaction_created_before(three_day_xact.created_at)
        .where(id: [three_day_line_item, week_line_item, day_line_item])

      refute_includes result, day_line_item
      refute_includes result, three_day_line_item
      assert_includes result, week_line_item
    end
  end

  context "validations" do
    test "disallows Marketplace subscribable with Sponsors listing" do
      marketplace_subscribable = create(:marketplace_listing_plan)
      sponsors_listing = create(:sponsors_listing)

      line_item = build(:billing_transaction_line_item, subscribable: marketplace_subscribable,
        listing: sponsors_listing)

      refute_predicate line_item, :valid?
      assert_includes line_item.errors[:listing_type],
        "does not match subscribable type for Marketplace"
    end

    test "disallows Sponsors subscribable with Marketplace listing" do
      sponsors_subscribable = create(:sponsors_tier, :published)
      marketplace_listing = create(:marketplace_listing)

      line_item = build(:billing_transaction_line_item, subscribable: sponsors_subscribable,
        listing: marketplace_listing)

      refute_predicate line_item, :valid?
      assert_includes line_item.errors[:listing_type],
        "does not match subscribable type for Sponsors"
    end

    test "disallows creating an item with Sponsors subscribable with PayPal-paid transaction" do
      sponsors_subscribable = create(:sponsors_tier, :published)
      transaction = create(:billing_transaction, payment_type: :paypal)

      line_item = build(:billing_transaction_line_item, subscribable: sponsors_subscribable,
        billing_transaction: transaction)

      refute_predicate line_item, :valid?
      assert_includes line_item.errors[:subscribable_type], "cannot be paid for using PayPal"
    end

    test "allows creating an item with Sponsors subscribable with credit card-paid transaction" do
      sponsors_subscribable = create(:sponsors_tier, :published)
      transaction = create(:billing_transaction, payment_type: :credit_card)

      line_item = build(:billing_transaction_line_item, subscribable: sponsors_subscribable,
        billing_transaction: transaction)

      assert_predicate line_item, :valid?
      assert_empty line_item.errors[:subscribable_type]
    end

    test "allows updating an item with Sponsors subscribable with PayPal-paid transaction" do
      sponsors_subscribable = create(:sponsors_tier, :published)
      transaction = create(:billing_transaction)
      line_item = create(:billing_transaction_line_item, subscribable: sponsors_subscribable,
        billing_transaction: transaction)
      transaction.update_attribute(:payment_type, :paypal)

      line_item.reload
      line_item.description += " updated"

      assert_predicate line_item, :valid?
      assert_empty line_item.errors[:subscribable_type]
    end

    test "requires listing when subscribable is set" do
      sponsors_subscribable = create(:sponsors_tier, :published)

      line_item = build(:billing_transaction_line_item, subscribable: sponsors_subscribable,
        listing: nil)

      refute_predicate line_item, :valid?
      assert_includes line_item.errors[:listing_id], "is required when there's a subscribable"
    end

    test "requires subscribable when listing is set" do
      marketplace_listing = create(:marketplace_listing)

      line_item = build(:billing_transaction_line_item, subscribable: nil,
        listing: marketplace_listing)

      refute_predicate line_item, :valid?
      assert_includes line_item.errors[:subscribable_id], "is required when there's a listing"
    end

    test "disallows subscribable to be for a different Sponsors listing on create" do
      tier = create(:sponsors_tier, :published)
      other_listing = create(:sponsors_listing)

      line_item = build(:billing_transaction_line_item, :sponsors, subscribable: tier, listing: other_listing)

      refute_predicate line_item, :valid?
      assert_includes line_item.errors[:subscribable_id], "is for a different listing"
    end

    test "disallows subscribable to be for a different Sponsors listing on update" do
      tier = create(:sponsors_tier, :published)
      line_item = create(:billing_transaction_line_item, :sponsors, subscribable: tier,
        listing: tier.sponsors_listing)
      other_listing = create(:sponsors_listing)

      line_item.listing = other_listing

      refute_predicate line_item, :valid?
      assert_includes line_item.errors[:subscribable_id], "is for a different listing"
    end

    test "disallows subscribable to be for a different Marketplace listing on create" do
      listing_plan = create(:marketplace_listing_plan)
      other_listing = create(:marketplace_listing)

      line_item = build(:billing_transaction_line_item, subscribable: listing_plan,
        listing: other_listing)

      refute_predicate line_item, :valid?
      assert_includes line_item.errors[:subscribable_id], "is for a different listing"
    end

    test "disallows subscribable to be for a different Marketplace listing on update" do
      listing_plan = create(:marketplace_listing_plan)
      line_item = create(:billing_transaction_line_item, subscribable: listing_plan,
        listing: listing_plan.listing)
      other_listing = create(:marketplace_listing)

      line_item.listing = other_listing

      refute_predicate line_item, :valid?
      assert_includes line_item.errors[:subscribable_id], "is for a different listing"
    end
  end

  context "scopes" do
    context ".marketplace" do
      test "includes marketplace listing plan line items" do
        assert_same_elements [@marketplace_plan_item], @transaction.line_items.marketplace
      end
    end

    context ".product_uuids" do
      test "includes product uuid line items" do
        assert_same_elements [@product_uuid_item, @copilot_item], @transaction.line_items.product_uuids
      end
    end

    context ".copilot" do
      test "includes copilot line items" do
        assert_same_elements [@copilot_item], @transaction.line_items.copilot
      end
    end

    context ".github" do
      test "includes non-subscribable line items" do
        assert_same_elements [@non_subscribable_item], @transaction.line_items.github
      end
    end

    context ".subscribable" do
      test "includes subscribable line items" do
        expected = [@marketplace_plan_item, @sponsors_tier_item, @product_uuid_item, @copilot_item]
        assert_same_elements expected, @transaction.line_items.subscribable
      end
    end

    context ".paid" do
      test "returns line items with a non-zero amount in cents" do
        zero_priced_item = create(:billing_transaction_line_item, amount_in_cents: 0)

        result = Billing::BillingTransaction::LineItem.paid

        assert_includes result, @sponsors_tier_item
        assert_includes result, @marketplace_plan_item
        refute_includes result, zero_priced_item
      end
    end

    context ".for_user" do
      test "includes line items whose billing transactions are for the specified user" do
        transaction1 = create(:billing_transaction)
        line_item1 = create(:billing_transaction_line_item, billing_transaction: transaction1)
        transaction2 = create(:billing_transaction)
        line_item2 = create(:billing_transaction_line_item, billing_transaction: transaction2)
        refute_equal transaction1.user, transaction2.user

        result = ::Billing::BillingTransaction::LineItem
          .for_user(transaction1.user_id)
          .where(id: [line_item1, line_item2])

        assert_includes result, line_item1
        refute_includes result, line_item2
      end
    end

    context ".for_subscribable" do
      test "works when given just the ID of the subscribable" do
        result = Billing::BillingTransaction::LineItem
          .sponsorships
          .for_subscribable(@sponsors_tier.id)
          .where(id: [@sponsors_tier_item, @marketplace_plan_item])

        assert_equal [@sponsors_tier_item], result
      end

      test "works when given the whole subscribable" do
        result = Billing::BillingTransaction::LineItem
          .for_subscribable(@marketplace_listing_plan)
          .where(id: [@sponsors_tier_item, @marketplace_plan_item])

        assert_equal [@marketplace_plan_item], result
      end
    end

    context ".for_sponsors_plan_subscription" do
      test "returns line items tied to billing transactions for a given plan subscription_id" do
        org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
        sponsors_plan_subscription = org.sponsors_plan_subscription
        transaction = create(:billing_transaction, plan_subscription_id: sponsors_plan_subscription.id)
        line_item = create(:billing_transaction_line_item, billing_transaction: transaction)
        result = Billing::BillingTransaction::LineItem
          .for_sponsors_plan_subscription(sponsors_plan_subscription.id)

        assert_equal [line_item], result
      end

      test "does not return line items unrelated to the plan subscription id" do
        transaction = create(:billing_transaction)
        result = Billing::BillingTransaction::LineItem
          .for_sponsors_plan_subscription(transaction.plan_subscription_id)

        assert_empty result
      end
    end

    context ".before_line_item" do
      test "includes line items created before the given one" do
        line_item1, line_item2, line_item3 = create_list(:billing_transaction_line_item, 3)

        result = Billing::BillingTransaction::LineItem.before_line_item(line_item2)
          .where(id: [line_item1, line_item2, line_item3])
          .pluck(:id)

        assert_includes result, line_item1.id, "should include line item created before given line item"
        refute_includes result, line_item2.id, "should not include given line item"
        refute_includes result, line_item3.id,
          "should not include line item created after given line item"
      end
    end

    context ".created_between" do
      test "returns line items that were created within a given time frame" do
        now = Time.current
        line_item = create(:billing_transaction_line_item, created_at: now)

        result = Billing::BillingTransaction::LineItem.created_between(now.yesterday, now.tomorrow)

        assert_includes result, line_item
      end

      test "does not return line items that were created outside of that time frame" do
        now = Time.current
        line_item = create(:billing_transaction_line_item, created_at: now)

        result = Billing::BillingTransaction::LineItem.created_between(now - 2.days, now.yesterday)

        refute_includes result, line_item
      end
    end

    context ".created_at_or_after" do
      test "includes line items created at or after the given time" do
        line_item1 = travel_to(1.week.ago) { create(:billing_transaction_line_item) }
        line_item2 = travel_to(1.day.ago) { create(:billing_transaction_line_item) }
        line_item3 = travel_to(1.hour.ago) { create(:billing_transaction_line_item) }

        result = Billing::BillingTransaction::LineItem.created_at_or_after(line_item2.created_at)
          .where(id: [line_item1, line_item2, line_item3])
          .pluck(:id)

        refute_includes result, line_item1.id, "should not include line item older than given time"
        assert_includes result, line_item2.id, "should include line item created at the given time"
        assert_includes result, line_item3.id, "should include line item created after the given time"
      end
    end
  end

  context "#create_tax_item_from_source" do
    test "returns the tax item created if it already exists by source ID and name" do
      line_item = create(:billing_transaction_line_item)
      zuora_tax_item = Billing::Zuora::TaxationItem.new(zuora_taxation_items_data_attributes)
      created_tax_item = assert_difference "Billing::BillingTransaction::TaxItem.count", 1 do
        line_item.create_tax_item_from_source(zuora_tax_item)
      end

      existing_tax_item = assert_no_difference "Billing::BillingTransaction::TaxItem.count" do
        line_item.create_tax_item_from_source(zuora_tax_item)
      end

      assert_equal created_tax_item, existing_tax_item
    end
  end

  context "#plan_subscription" do
    test "returns the plan subscription recorded on the billing transaction" do
      plan_sub = create(:billing_plan_subscription, :sponsors_invoiced)
      transaction = create(:billing_transaction, plan_subscription: plan_sub)
      line_item = create(:billing_transaction_line_item, billing_transaction: transaction)
      assert_equal plan_sub, line_item.plan_subscription
    end

    test "falls back to the user's general-purpose plan subscription when billing transaction does not have one" do
      plan_sub = create(:billing_plan_subscription)
      user = plan_sub.user
      transaction = create(:billing_transaction, plan_subscription_id: nil, user: user)
      line_item = create(:billing_transaction_line_item, billing_transaction: transaction)
      assert_equal plan_sub, line_item.plan_subscription
    end
  end

  context "#paid?" do
    test "returns true when amount_in_cents is greater than zero" do
      paid_line_item = create(:billing_transaction_line_item, amount_in_cents: 1)
      assert paid_line_item.paid?
    end

    test "returns false when amount_in_cents is zero" do
      free_line_item = create(:billing_transaction_line_item, amount_in_cents: 0)
      refute free_line_item.paid?
    end
  end

  context "subscribable?" do
    test "returns true when the line item has a subscribable association" do
      assert @sponsors_tier_item.subscribable?
    end

    test "returns false when the line item does not have a subscribable association" do
      refute @non_subscribable_item.subscribable?
    end
  end

  context "marketplace?" do
    test "returns true when the line item is for a Marketplace::ListingPlan" do
      assert @marketplace_plan_item.marketplace?
    end

    test "returns false when the line item is not for a Marketplace::ListingPlan" do
      refute @sponsors_tier_item.marketplace?
    end
  end

  context "sponsorship?" do
    test "returns true when the line item is for a SponsorsTier" do
      assert @sponsors_tier_item.sponsorship?
    end

    test "returns false when the line item is not for a SponsorsTier" do
      refute @marketplace_plan_item.sponsorship?
    end
  end

  context "product_uuid?" do
    test "returns true when the line item is for a Billing::ProductUUID" do
      assert @product_uuid_item.product_uuid?
    end

    test "returns false when the line item is not for a Billing::ProductUUID" do
      refute @marketplace_plan_item.product_uuid?
    end
  end

  context "copilot?" do
    test "returns true when the line item is for a Copilot Billing::ProductUUID" do
      assert @copilot_item.copilot?
    end

    test "returns false when the line item is not for a Copilot Billing::ProductUUID" do
      refute @product_uuid_item.copilot?
    end
  end

  context "#billing_transaction_for_user?" do
    test "true when line item's billing transaction is for the user with the given ID" do
      user_id = @transaction.user_id
      assert @sponsors_tier_item.billing_transaction_for_user?(user_id)
    end

    test "false when line item's billing transaction is for a different user" do
      other_user = create(:user)
      refute @sponsors_tier_item.billing_transaction_for_user?(other_user.id)
    end
  end

  context "#core_count_from_description" do
    test "extracts core information from description" do
      transaction = create(:billing_transaction)
      line_item = Billing::BillingTransaction::LineItem.create!(
        billing_transaction: transaction,
        description: "GitHub Codespaces - Compute D32 Usage",
        quantity: 1,
        amount_in_cents: 100,
        arr_in_cents: 1200,
      )

      assert_equal "32 core", line_item.core_count_from_description
    end
  end

  context "#copilot_sku_description" do
    test "returns the description for Copilot Business" do
      transaction = create(:billing_transaction)
      line_item = Billing::BillingTransaction::LineItem.create!(
        billing_transaction: transaction,
        description: "GitHub Copilot",
        quantity: 1,
        amount_in_cents: 100,
        arr_in_cents: 1200,
      )

      assert_equal "Business", line_item.copilot_sku_description
    end

    test "returns the description for Copilot Enterprise" do
      transaction = create(:billing_transaction)
      line_item = Billing::BillingTransaction::LineItem.create!(
        billing_transaction: transaction,
        description: "GitHub Copilot Enterprise",
        quantity: 1,
        amount_in_cents: 100,
        arr_in_cents: 1200,
      )

      assert_equal "Enterprise", line_item.copilot_sku_description
    end

    test "returns the description for Copilot Standalone" do
      transaction = create(:billing_transaction)
      line_item = Billing::BillingTransaction::LineItem.create!(
        billing_transaction: transaction,
        description: "GitHub Copilot Standalone",
        quantity: 1,
        amount_in_cents: 100,
        arr_in_cents: 1200,
      )

      assert_equal "Business", line_item.copilot_sku_description
    end

    test "returns 'Unknown' when the description is not for Copilot" do
      transaction = create(:billing_transaction)
      line_item = Billing::BillingTransaction::LineItem.create!(
        billing_transaction: transaction,
        description: "GitHub Codespaces - Compute D32 Usage",
        quantity: 1,
        amount_in_cents: 100,
        arr_in_cents: 1200,
      )

      assert_equal "Unknown", line_item.copilot_sku_description
    end
  end
end
