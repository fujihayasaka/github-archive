# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::BillingTransaction::LineItem::SponsorsDependencyTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include HydroTestHelpers

  skip_unless :sponsors_enabled?

  fixtures do
    @transaction = create :billing_transaction
    @transaction.statuses.create amount_in_cents: 1200, status: :authorized

    @marketplace_listing_plan = create(:marketplace_listing_plan, :published)
    @marketplace_plan_item = create(:billing_transaction_line_item,
      billing_transaction: @transaction, subscribable: @marketplace_listing_plan)

    @sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing)
    @sponsors_tier_item = create(:billing_transaction_line_item, billing_transaction: @transaction,
      subscribable: @sponsors_tier)

    @fiscal_host_listing = create(:sponsors_listing, :fiscal_host)
    @fiscal_stripe = create(:stripe_connect_account, sponsors_listing: @fiscal_host_listing)
    @child_listing = create(:sponsors_listing, :approved, :with_fiscal_host,
      parent_listing: @fiscal_host_listing)
    @child_tier = create(:sponsors_tier, :published, sponsors_listing: @child_listing)
    child_transaction = create :billing_transaction
    child_transaction.statuses.create amount_in_cents: 1200, status: :authorized
    @child_tier_item = create(:billing_transaction_line_item,
      billing_transaction: child_transaction, subscribable: @child_tier)
  end

  context "sponsorships_excluding_prorated scope" do
    test "includes line items for non-prorated sponsorships" do
      line_item = create(:billing_transaction_line_item, :sponsors, :with_sponsorship)

      result = Billing::BillingTransaction::LineItem.sponsorships_excluding_prorated
      assert_includes result, line_item
    end

    test "makes X queries" do
      # some normal line items
      create(:billing_transaction_line_item, :sponsors, :with_sponsorship)
      create(:billing_transaction_line_item, :sponsors, :with_sponsorship)
      # prorated line item
      transaction = create(:billing_transaction, :prorated)
      create(:billing_transaction_line_item, billing_transaction: transaction,
        subscribable: @sponsors_tier, amount_in_cents: @sponsors_tier.monthly_price_in_cents / 2)

      assert_query_count_per_table({
        billing_transaction_line_items: 1,
        sponsors_tiers: 1,
      }) do
        Billing::BillingTransaction::LineItem.sponsorships_excluding_prorated
      end
    end

    test "excludes line items for prorated sponsorships" do
      transaction = create(:billing_transaction, :prorated)
      prorated_line_item = create(:billing_transaction_line_item, billing_transaction: transaction,
        subscribable: @sponsors_tier, amount_in_cents: @sponsors_tier.monthly_price_in_cents / 2)

      result = Billing::BillingTransaction::LineItem.sponsorships_excluding_prorated
      refute_includes result, prorated_line_item
    end

    test "excludes non-sponsorship line items" do
      result = Billing::BillingTransaction::LineItem.sponsorships_excluding_prorated
      refute_includes result, @marketplace_plan_item
    end
  end

  context "sponsorships scope" do
    test "includes sponsors tier line items" do
      result = @transaction.line_items.sponsorships

      assert_includes result, @sponsors_tier_item
      refute_includes result, @marketplace_plan_item
    end
  end

  context "#sponsors_fee?" do
    test "returns false for non-fee Sponsors line item" do
      tier = create(:sponsors_tier)
      invoice_item = Billing::Zuora::SubscribableInvoiceItem.new({
        "unitPrice" => tier.monthly_price_in_dollars,
        "chargeName" => tier.sponsors_listing.monthly_plan_or_charge_name,
        "chargeAmount" => tier.monthly_price_in_dollars,
        "quantity" => 1.0,
        "serviceStartDate" => "2022-09-22",
        "serviceEndDate" => "2022-10-21",
      }, subscribable: tier)
      description = tier.line_item_description(invoice_item: invoice_item)
      refute description.ends_with?("fee")
      line_item = create(:billing_transaction_line_item, description: description, subscribable: tier)

      refute_predicate line_item, :sponsors_fee?
    end

    test "returns false for non-Sponsors line item" do
      line_item = create(:billing_transaction_line_item, description: "GitHub Package Registry - Data Transfer")
      refute_predicate line_item, :sponsors_fee?
    end

    test "returns true for Sponsors fee line item" do
      tier = create(:sponsors_tier)
      invoice_item = Billing::Zuora::SubscribableInvoiceItem.new({
        "unitPrice" => tier.monthly_price_in_dollars,
        "chargeName" => SponsorsListing.fee_charge_name_for(tier.sponsors_listing.monthly_plan_or_charge_name),
        "chargeAmount" => 0.15,
        "quantity" => 1.0,
        "serviceStartDate" => "2022-09-22",
        "serviceEndDate" => "2022-10-21",
      }, subscribable: tier)
      description = tier.line_item_description(invoice_item: invoice_item)
      assert description.ends_with?("fee")
      line_item = create(:billing_transaction_line_item, description: description, subscribable: tier)

      assert_predicate line_item, :sponsors_fee?
    end
  end

  context "paying_sponsorable scope" do
    test "includes line items with a Sponsors tier for the specified sponsorable" do
      other_sponsors_item = create(:billing_transaction_line_item, :sponsors)
      other_tier_same_maintainer = create(:sponsors_tier, :custom, sponsors_listing: @sponsors_tier.sponsors_listing)
      sponsors_tier_item2 = create(:billing_transaction_line_item, subscribable: other_tier_same_maintainer)

      result = Billing::BillingTransaction::LineItem.paying_sponsorable(@sponsors_tier.sponsorable)

      assert_includes result, @sponsors_tier_item
      assert_includes result, sponsors_tier_item2,
        "should include Sponsors line item from same maintainer using a different tier"
      refute_includes result, other_sponsors_item, "should not include Sponsors line item from another maintainer"
      refute_includes result, @marketplace_plan_item, "should not include non-Sponsors line item"
    end
  end

  context "sponsorship relation" do
    test "gets sponsorship when line item subscribable matches sponsorship tier" do
      sponsor = @transaction.user
      sponsorship = create(:sponsorship, tier: @sponsors_tier, sponsor: sponsor)

      assert_equal sponsorship, @sponsors_tier_item.sponsorship
    end

    test "gets sponsorship when line item subscribable doesn't match sponsorship tier" do
      sponsor = @transaction.user
      other_tier = create(:sponsors_tier, :published, sponsors_listing: @sponsors_tier.sponsors_listing)
      sponsorship = create(:sponsorship, tier: other_tier, sponsor: sponsor)

      assert_equal sponsorship, @sponsors_tier_item.sponsorship
    end

    test "returns nil for Marketplace line item" do
      assert_nil @marketplace_plan_item.sponsorship
    end

    test "returns related sponsorship for Sponsors tier line item" do
      sponsorship = create(:sponsorship, tier: @sponsors_tier)
      transaction = create(:billing_transaction, user: sponsorship.sponsor,
        amount_in_cents: @sponsors_tier.monthly_price_in_cents)
      line_item = create(:billing_transaction_line_item, billing_transaction: transaction,
          subscribable: @sponsors_tier, amount_in_cents: @sponsors_tier.monthly_price_in_cents,
          quantity: 1, description: "GitHub Sponsors - #{sponsorship.sponsorable} sponsorship")

      assert_equal sponsorship, line_item.sponsorship
    end

    test "returns sponsorship enterprise account member org" do
      sub_item = create(:sponsors_subscription_item, :self_serve_business, subscribable: @sponsors_tier)
      sponsorship = create(:sponsorship,
        sponsor: sub_item.organization,
        tier: @sponsors_tier,
        subscription_item: sub_item
      )
      transaction = create(:billing_transaction, :business_owned, customer: sub_item.customer)
      line_item = create(:billing_transaction_line_item,
        billing_transaction: transaction,
        subscribable: @sponsors_tier,
        amount_in_cents: @sponsors_tier.monthly_price_in_cents,
        extras: { managing_entity_id: sub_item.organization_id }
      )

      assert_equal sponsorship, line_item.sponsorship
    end
  end

  context "#sponsor_id" do
    test "returns managing entity if it exists" do
      managing_entity_id = 42

      line_item = create(:billing_transaction_line_item,
        billing_transaction: @transaction,
        subscribable: @sponsors_tier,
        amount_in_cents: @sponsors_tier.monthly_price_in_cents,
        extras: { managing_entity_id: managing_entity_id }
      )

      assert_equal managing_entity_id, line_item.sponsor_id
    end

    test "returns billable entity if no managing entity" do
      line_item = create(:billing_transaction_line_item,
        billing_transaction: @transaction,
        subscribable: @sponsors_tier,
        amount_in_cents: @sponsors_tier.monthly_price_in_cents
      )

      assert_equal line_item.billing_transaction_user_id, line_item.sponsor_id
    end
  end

  context "#sponsor" do
    test "returns managing entity for enterprise account transactions" do
      managing_entity = create(:organization)

      transaction = create(:billing_transaction, :business_owned)
      line_item = create(:billing_transaction_line_item,
        billing_transaction: transaction,
        subscribable: @sponsors_tier,
        amount_in_cents: @sponsors_tier.monthly_price_in_cents,
        extras: { managing_entity_id: managing_entity.id }
      )

      assert_equal managing_entity, line_item.sponsor
    end

    test "returns user for user transactions" do
      line_item = create(:billing_transaction_line_item,
        billing_transaction: @transaction,
        subscribable: @sponsors_tier,
        amount_in_cents: @sponsors_tier.monthly_price_in_cents
      )

      assert_equal line_item.user, line_item.sponsor
    end
  end

  context "#sponsorable" do
    test "returns the sponsorable from the Sponsors tier" do
      assert_equal @sponsors_tier.sponsorable, @sponsors_tier_item.sponsorable
    end

    test "returns nil for non-Sponsors line item" do
      assert_nil @marketplace_plan_item.sponsorable
    end
  end

  context "on create" do
    test "deactivates subscription item for one-time sponsorship payment" do
      sponsors_listing = @sponsors_tier.sponsors_listing
      sponsorable = sponsors_listing.sponsorable
      one_time_tier = create(:sponsors_tier, :published, :one_time,
        sponsors_listing: sponsors_listing
      )
      sponsorship = create(:sponsorship,
        tier: one_time_tier,
      )
      transaction = create(:billing_transaction, user: sponsorship.sponsor,
        plan_subscription: sponsorship.plan_subscription,
        amount_in_cents: one_time_tier.monthly_price_in_cents)

      assert_predicate sponsorship.subscription_item, :active?

      create(:billing_transaction_line_item, billing_transaction: transaction,
        subscribable: one_time_tier, amount_in_cents: one_time_tier.monthly_price_in_cents,
        quantity: 1, description: "GitHub Sponsors - #{sponsorship.sponsorable} sponsorship")

      assert_predicate sponsorship.reload_subscription_item, :cancelled?
    end

    test "does not deactivate subscription item for recurring sponsorship payment" do
      sponsors_listing = @sponsors_tier.sponsors_listing
      sponsorable = sponsors_listing.sponsorable
      sponsorship = create(:sponsorship,
        tier: @sponsors_tier,
      )
      transaction = create(:billing_transaction, user: sponsorship.sponsor,
        amount_in_cents: @sponsors_tier.monthly_price_in_cents)

      assert_predicate sponsorship.subscription_item, :active?

      create(:billing_transaction_line_item, billing_transaction: transaction,
        subscribable: @sponsors_tier, amount_in_cents: @sponsors_tier.monthly_price_in_cents,
        quantity: 1, description: "GitHub Sponsors - #{sponsorship.sponsorable} sponsorship")

      assert_predicate sponsorship.reload_subscription_item, :active?
    end

    test "deactivates subscription item for concurrent one-time sponsorship payment" do
      sponsors_listing = @sponsors_tier.sponsors_listing
      sponsorable = sponsors_listing.sponsorable
      one_time_tier = create(:sponsors_tier, :published, :one_time,
        sponsors_listing: sponsors_listing
      )
      sponsorship = create(:sponsorship,
        tier: @sponsors_tier,
      )
      sponsor = sponsorship.sponsor
      one_time_subscription_item = create(:sponsors_subscription_item,
        plan_subscription: sponsorship.plan_subscription,
        subscribable: one_time_tier,
      )

      assert_predicate sponsorship, :recurring_payment?, "concurrency requires existing recurring sponsorship"
      assert_predicate one_time_subscription_item, :active?, "requires active concurrent one-time subscription item"

      transaction = create(:billing_transaction, user: sponsor,
        plan_subscription: one_time_subscription_item.plan_subscription,
        amount_in_cents: one_time_tier.monthly_price_in_cents)

      create(:billing_transaction_line_item, billing_transaction: transaction,
        subscribable: one_time_tier, amount_in_cents: one_time_tier.monthly_price_in_cents,
        quantity: 1, description: "GitHub Sponsors - #{sponsorable} sponsorship")

      assert_predicate sponsorship.reload_subscription_item, :active?
      assert_predicate one_time_subscription_item.reload, :cancelled?
    end
  end

  context "sponsors_listing relation" do
    test "returns SponsorsListing tied to the tier used by the line item" do
      listing = create(:sponsors_listing, :approved, tier_count: 0)
      tier = create(:sponsors_tier, :published, sponsors_listing: listing)
      line_item = create(:billing_transaction_line_item, subscribable: tier)

      assert_equal listing, line_item.sponsors_listing
    end

    test "returns nil when line item does not have a SponsorsTier subscribable" do
      assert_nil @marketplace_plan_item.sponsors_listing
    end
  end

  context "#sponsors_stripe_transfer_account_id" do
    test "returns Stripe account ID for the line item's Sponsors listing" do
      stripe_account = create(:stripe_connect_account, sponsors_listing: @sponsors_tier.sponsors_listing)
      assert_equal stripe_account.stripe_account_id,
        @sponsors_tier_item.sponsors_stripe_transfer_account_id
    end

    test "returns Stripe account ID for the line item's Sponsors listing's parent listing" do
      assert_equal @fiscal_stripe.stripe_account_id,
        @child_tier_item.sponsors_stripe_transfer_account_id
    end

    test "returns nil when Sponsors listing for line item does not have a Stripe account" do
      assert_predicate @sponsors_tier_item, :listing_SponsorsListing?,
        "need a line item for a Sponsors listing"
      assert_nil @sponsors_tier_item.listing&.active_stripe_connect_account,
        "need a line item for a Sponsors listing that doesn't have a Stripe account"
      assert_nil @sponsors_tier_item.sponsors_stripe_transfer_account_id
    end

    test "returns nil when line item does not have a Sponsors listing" do
      refute_predicate @marketplace_plan_item, :listing_SponsorsListing?,
        "need a line item without a Sponsors listing"
      assert_nil @marketplace_plan_item.sponsors_stripe_transfer_account_id
    end
  end

  context "#stripe_transfers_enabled?" do
    test "true when line item is for a Sponsors listing that has a Stripe account" do
      create(:stripe_connect_account, sponsors_listing: @sponsors_tier.sponsors_listing)
      assert_predicate @sponsors_tier_item, :stripe_transfers_enabled?
    end

    test "false when line item is for a Sponsors listing that does not have a Stripe account" do
      assert_nil @sponsors_tier.sponsors_listing.active_stripe_connect_account,
        "need Sponsors listing to not have a Stripe account"
      refute_predicate @sponsors_tier_item, :stripe_transfers_enabled?
    end

    test "false when line item is not for a Sponsors listing" do
      refute_predicate @marketplace_plan_item, :stripe_transfers_enabled?
    end
  end

  context "sponsorships scope" do
    test "includes sponsors tiers" do
      expected_sponsorships = [@sponsors_tier_item]
      assert_same_elements expected_sponsorships, @transaction.line_items.sponsorships
    end
  end
end
