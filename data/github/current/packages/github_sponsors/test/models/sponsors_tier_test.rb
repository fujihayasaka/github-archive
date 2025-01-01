# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsTierTest < GitHub::TestCase
  include GitHub::BillingTest

  fixtures do
    @listing = create(:sponsors_listing, :approved)
    @sponsorable = @listing.sponsorable

    @draft_tier = create(:sponsors_tier, :approved_sponsors_listing, :draft)
    @published_tier = create(:sponsors_tier, :approved_sponsors_listing, :published)
    @retired_tier = create(:sponsors_tier, :approved_sponsors_listing, :retired)
    @custom_tier = create(:sponsors_tier, :approved_sponsors_listing, :custom,
      monthly_price_in_cents: 100_00, frequency: :recurring)
    @invoiced_tier = create(:sponsors_tier, :approved_sponsors_listing, :invoiced)
    @tier_with_repo = create(:sponsors_tier, :approved_sponsors_listing, :with_repository)
  end

  setup do
    @published_tier_listing = @published_tier.sponsors_listing
  end

  context "#same_listing?" do
    test "returns false when given something other than a Sponsors tier" do
      refute @draft_tier.same_listing?(nil)
      refute @draft_tier.same_listing?(create(:marketplace_listing_plan))
    end

    test "returns true when given the same tier" do
      assert @draft_tier.same_listing?(@draft_tier)
    end

    test "returns true when given a different tier from the same Sponsors listing" do
      other_tier = create(:sponsors_tier, sponsors_listing: @draft_tier.sponsors_listing)
      assert @draft_tier.same_listing?(other_tier)
    end

    test "returns false when given a different tier from a different Sponsors listing" do
      refute_equal @draft_tier.sponsors_listing, @published_tier_listing, "need tiers from two listings"
      refute @draft_tier.same_listing?(@published_tier)
    end
  end

  context "#sponsorable_login" do
    test "returns login from sponsorable relation when loaded" do
      tier = SponsorsTier.find(@listing.default_tier.id) # make sure no relations are loaded on the tier
      GitHub::PrefillAssociations.prefill_associations([tier], :sponsorable, available_records: [@sponsorable])

      assert_query_count(0) do
        assert_equal @sponsorable.login, tier.sponsorable_login
      end
    end

    test "returns sponsorable_login from listing relation when sponsorable relation is not loaded" do
      tier = @listing.default_tier
      refute_predicate tier.association(:sponsorable), :loaded?
      assert_predicate tier.association(:sponsors_listing), :loaded?

      assert_query_count(0) do
        assert_equal @listing.sponsorable_login, tier.sponsorable_login
      end
    end
  end

  context "with_monthly_price_in_cents scope" do
    test "returns tiers with the exact monthly price specified" do
      low_tier = @draft_tier
      exact_tier = create(:sponsors_tier, monthly_price_in_cents: low_tier.monthly_price_in_cents + 100)
      high_tier = create(:sponsors_tier, monthly_price_in_cents: exact_tier.monthly_price_in_cents + 100)

      result = SponsorsTier.with_monthly_price_in_cents(exact_tier.monthly_price_in_cents)
        .where(id: [low_tier, exact_tier, high_tier])

      refute_includes result, low_tier
      assert_includes result, exact_tier
      refute_includes result, high_tier
    end
  end

  context "monthly_price_in_dollars_at_most scope" do
    test "returns tiers with monthly price in dollars <= the given value" do
      high_tier = @custom_tier
      low_tier = @draft_tier
      assert_operator high_tier.monthly_price_in_dollars, :>, low_tier.monthly_price_in_dollars,
        "need two tiers with different values"

      result = SponsorsTier.monthly_price_in_dollars_at_most(high_tier.monthly_price_in_dollars)
        .where(id: [high_tier.id, low_tier.id])
      assert_same_elements [high_tier, low_tier], result,
        "should include tier at the exact value given and tiers below"

      result = SponsorsTier.monthly_price_in_dollars_at_most(high_tier.monthly_price_in_dollars - 1)
        .where(id: [high_tier.id, low_tier.id])
      assert_equal [low_tier], result, "should exclude tier whose value exceeds amount given"
    end
  end

  context "monthly_price_in_cents_at_most scope" do
    test "returns tiers with monthly_price_in_cents <= the given value" do
      high_tier = @custom_tier
      low_tier = @draft_tier
      assert_operator high_tier.monthly_price_in_cents, :>, low_tier.monthly_price_in_cents,
        "need two tiers with different values"

      result = SponsorsTier.monthly_price_in_cents_at_most(high_tier.monthly_price_in_cents)
        .where(id: [high_tier.id, low_tier.id])
      assert_same_elements [high_tier, low_tier], result,
        "should include tier at the exact value given and tiers below"

      result = SponsorsTier.monthly_price_in_cents_at_most(high_tier.monthly_price_in_cents - 1_00)
        .where(id: [high_tier.id, low_tier.id])
      assert_equal [low_tier], result, "should exclude tier whose value exceeds amount given"
    end
  end

  context "with_recurrence scope" do
    test "filters to tiers that recur as specified" do
      recurring_tier = @published_tier
      assert_predicate recurring_tier, :recurring?
      one_time_tier = create(:sponsors_tier, :one_time)

      result = SponsorsTier.with_recurrence(true).where(id: [recurring_tier.id, one_time_tier.id])
      assert_equal [recurring_tier], result

      result = SponsorsTier.with_recurrence(false).where(id: [recurring_tier.id, one_time_tier.id])
      assert_equal [one_time_tier], result
    end
  end

  context "highest_monthly_price_first scope" do
    test "sorts tiers by monthly price in descending order" do
      high_tier = @custom_tier
      low_tier = @draft_tier
      assert_operator high_tier.monthly_price_in_cents, :>, low_tier.monthly_price_in_cents,
        "need two tiers with different values"

      result = SponsorsTier.highest_monthly_price_first.where(id: [high_tier.id, low_tier.id])

      assert_equal [high_tier, low_tier], result
    end
  end

  context "#for_organization?" do
    test "true for a tier for an organization's Sponsors listing" do
      org_listing = create(:sponsors_listing, :for_org)
      tier = build(:sponsors_tier, sponsors_listing: org_listing)
      assert_predicate tier, :for_organization?
    end

    test "false for a tier for an user's Sponsors listing" do
      assert_predicate @draft_tier.sponsorable, :user?, "need a user sponsorable"
      refute_predicate @draft_tier, :for_organization?
    end
  end

  context "#has_repository?" do
    test "true when the tier has an associated repository" do
      refute_nil @tier_with_repo.repository
      assert_predicate @tier_with_repo, :has_repository?
    end

    test "false when the tier does not have an associated repository" do
      assert_nil @published_tier.repository
      refute_predicate @published_tier, :has_repository?
    end

    test "true for a custom tier whose parent tier has a repository" do
      tier = build(:sponsors_tier, :custom, parent_tier: @tier_with_repo,
        sponsors_listing: @tier_with_repo.sponsors_listing,
        monthly_price_in_cents: @tier_with_repo.monthly_price_in_cents + 100)
      assert_predicate tier, :has_repository?
    end

    test "false for a custom tier whose parent tier does not have a repository" do
      tier = build(:sponsors_tier, :custom, parent_tier: @published_tier,
        sponsors_listing: @published_tier_listing,
        monthly_price_in_cents: @published_tier.monthly_price_in_cents + 100)
      refute_predicate tier, :has_repository?
    end

    test "true for a custom tier without a parent but that has a closer lesser-value tier with a repository" do
      tier = build(:sponsors_tier, :custom, parent_tier: nil,
        sponsors_listing: @tier_with_repo.sponsors_listing,
        monthly_price_in_cents: @tier_with_repo.monthly_price_in_cents + 100)
      assert_equal @tier_with_repo, tier.closest_lesser_value_tier,
        "need tier to have its closest lesser-value tier be one with a repository"
      assert_predicate tier, :has_repository?
    end

    test "false for a custom tier without a parent and whose closer lesser-value tier does not have a repository" do
      tier = build(:sponsors_tier, :custom, parent_tier: nil,
        sponsors_listing: @published_tier_listing,
        monthly_price_in_cents: @published_tier.monthly_price_in_cents + 100)
      assert_equal @published_tier, tier.closest_lesser_value_tier,
        "need tier to have its closest lesser-value tier be one without a repository"
      refute_predicate tier, :has_repository?
    end
  end

  context "for_sponsorable scope" do
    test "includes tiers for a given maintainer's listing" do
      draft_tier = create(:sponsors_tier, :draft, sponsors_listing: @listing)
      custom_tier = create(:sponsors_tier, :custom, sponsors_listing: @listing)
      retired_tier = create(:sponsors_tier, :retired, sponsors_listing: @listing)
      one_time_tier = create(:sponsors_tier, :one_time, sponsors_listing: @listing)
      published_tier = @listing.default_tier
      invoiced_tier = create(:sponsors_tier, :invoiced, sponsors_listing: @listing)

      result = SponsorsTier.for_sponsorable(@sponsorable)

      assert_same_elements [draft_tier, custom_tier, retired_tier, one_time_tier, published_tier,
        invoiced_tier], result
    end
  end

  context "with_active_sponsorships scope" do
    test "includes only tiers that have active sponsorships" do
      create(:sponsorship, tier: @published_tier)

      result = SponsorsTier.with_active_sponsorships
        .where(id: [@draft_tier, @published_tier, @retired_tier, @custom_tier])
        .pluck(:id)

      assert_includes result, @published_tier.id, "should include published tier that is in use"
      refute_includes result, @draft_tier.id, "should not include draft tier"
      refute_includes result, @retired_tier.id, "should not include retired tier that is not in use"
      refute_includes result, @custom_tier.id, "shoult not include custom tier that is not in use"
    end
  end

  context "#publicly_visible?" do
    test "true for published tier on an approved listing" do
      assert_predicate @published_tier, :publicly_visible?
    end

    test "false for published tier on an unapproved listing" do
      draft_listing = create(:sponsors_listing, :draft)
      tier = build(:sponsors_tier, :published, sponsors_listing: draft_listing)
      refute_predicate tier, :publicly_visible?
    end

    test "false for retired tier on an approved listing" do
      refute_predicate @retired_tier, :publicly_visible?
    end

    test "false for custom tier on an approved listing" do
      refute_predicate @custom_tier, :publicly_visible?
    end

    test "false for invoiced tier on an approved listing" do
      refute_predicate @invoiced_tier, :publicly_visible?
    end
  end

  context "for_listing scope" do
    test "filters tiers based on the Sponsors listing" do
      refute_equal @draft_tier.sponsors_listing_id, @published_tier_listing_id,
        "need tiers from two different listings"

      result = SponsorsTier.for_listing(@draft_tier.sponsors_listing)
        .where(id: [@draft_tier, @published_tier])

      assert_includes result, @draft_tier
      refute_includes result, @published_tier
    end
  end

  context "#formatted_monthly_price" do
    test "returns a whole-dollar amount formatted nicely" do
      tier = SponsorsTier.new(monthly_price_in_cents: 200)
      assert_equal "$2", tier.formatted_monthly_price
    end
  end

  context "#formatted_price_per_cycle" do
    test "one-time tier with monthly billed sponsor" do
      sponsor = create(:credit_card_user, :verified,
        plan_subscription: create(:billing_plan_subscription),
        plan: GitHub::Plan.free_with_addons,
        plan_duration: "month"
      )
      tier = build(:sponsors_tier, :one_time, monthly_price_in_cents: 200)
      assert_equal "$2 one time", tier.formatted_price_per_cycle(sponsor: sponsor)
    end

    test "one-time tier with yearly billed sponsor" do
      sponsor = create(:credit_card_user, :verified,
        plan_subscription: create(:billing_plan_subscription),
        plan: GitHub::Plan.free_with_addons,
        plan_duration: "year"
      )
      tier = build(:sponsors_tier, :one_time, monthly_price_in_cents: 200)
      assert_equal "$2 one time", tier.formatted_price_per_cycle(sponsor: sponsor)
    end

    test "recurring tier with monthly billed sponsor" do
      sponsor = create(:credit_card_user, :verified,
        plan_subscription: create(:billing_plan_subscription),
        plan: GitHub::Plan.free_with_addons,
        plan_duration: "month"
      )
      tier = build(:sponsors_tier, monthly_price_in_cents: 200)
      assert_equal "$2 a month", tier.formatted_price_per_cycle(sponsor: sponsor)
    end

    test "recurring tier with yearly billed sponsor" do
      sponsor = create(:credit_card_user, :verified,
        plan_subscription: create(:billing_plan_subscription),
        plan: GitHub::Plan.free_with_addons,
        plan_duration: "year"
      )
      tier = build(:sponsors_tier, monthly_price_in_cents: 200)
      assert_equal "$24 a year", tier.formatted_price_per_cycle(sponsor: sponsor)
    end
  end

  context "#price_in_cents_per_cycle" do
    test "one-time tier with monthly billed sponsor" do
      tier = build(:sponsors_tier, :one_time, monthly_price_in_cents: 200)
      assert_equal 200, tier.price_in_cents_per_cycle(plan_duration: "month")
    end

    test "one-time tier with yearly billed sponsor" do
      tier = build(:sponsors_tier, :one_time, monthly_price_in_cents: 200)
      assert_equal 200, tier.price_in_cents_per_cycle(plan_duration: "year")
    end

    test "recurring tier with monthly billed sponsor" do
      tier = build(:sponsors_tier, monthly_price_in_cents: 200)
      assert_equal 200, tier.price_in_cents_per_cycle(plan_duration: "month")
    end

    test "recurring tier with yearly billed sponsor" do
      tier = build(:sponsors_tier, monthly_price_in_cents: 200)
      assert_equal 2400, tier.price_in_cents_per_cycle(plan_duration: "year")
    end
  end

  context "#stripe_transfers_enabled?" do
    test "true when tier belongs to a listing that has a Stripe account" do
      create(:stripe_connect_account, sponsors_listing: @published_tier_listing)
      assert_predicate @published_tier, :stripe_transfers_enabled?
    end

    test "false when tier belongs to a listing that does not have a Stripe account" do
      assert_nil @published_tier_listing.active_stripe_connect_account,
        "need a tier for a listing that doesn't have a Stripe account"
      refute_predicate @published_tier, :stripe_transfers_enabled?
    end
  end

  context "#available_for_purchase?" do
    test "true when tier is published" do
      tier = build(:sponsors_tier, :published)
      assert_predicate tier, :available_for_purchase?
    end

    test "true when tier is custom" do
      tier = build(:sponsors_tier, :custom)
      assert_predicate tier, :available_for_purchase?
    end

    test "false when tier is a draft" do
      tier = build(:sponsors_tier, :draft)
      refute_predicate tier, :available_for_purchase?
    end

    test "false when tier is retired" do
      tier = build(:sponsors_tier, :retired)
      refute_predicate tier, :available_for_purchase?
    end

    test "false when tier is invoiced" do
      assert_predicate @invoiced_tier, :invoiced?
      refute_predicate @invoiced_tier, :available_for_purchase?
    end
  end

  context "#available_for_sponsorship?" do
    test "true when tier is published" do
      tier = build(:sponsors_tier, :published)
      assert_predicate tier, :available_for_sponsorship?
    end

    test "true when tier is custom" do
      tier = build(:sponsors_tier, :custom)
      assert_predicate tier, :available_for_sponsorship?
    end

    test "true when tier is invoiced" do
      assert_predicate @invoiced_tier, :invoiced?
      assert_predicate @invoiced_tier, :available_for_sponsorship?
    end

    test "false when tier is a draft" do
      tier = build(:sponsors_tier, :draft)
      refute_predicate tier, :available_for_sponsorship?
    end

    test "false when tier is retired" do
      tier = build(:sponsors_tier, :retired)
      refute_predicate tier, :available_for_sponsorship?
    end
  end

  context "#current_state_name" do
    test "returns draft for state 0" do
      tier = SponsorsTier.new(state: :draft)
      assert_equal 0, tier.state
      assert_equal :draft, tier.current_state_name
    end

    test "returns published for state 1" do
      tier = SponsorsTier.new(state: :published)
      assert_equal 1, tier.state
      assert_equal :published, tier.current_state_name
    end

    test "returns retired for state 2" do
      tier = SponsorsTier.new(state: :retired)
      assert_equal 2, tier.state
      assert_equal :retired, tier.current_state_name
    end

    test "returns invoiced for state 4" do
      assert_equal 4, @invoiced_tier.state
      assert_equal :invoiced, @invoiced_tier.current_state_name
    end
  end

  context "billing associations" do
    test "doesn't allow deletion when there are associated subscription items" do
      create(:sponsors_subscription_item, subscribable: @published_tier)

      refute @published_tier.destroy
      assert_includes @published_tier.errors[:base], "Cannot delete record because dependent subscription items exist"
    end

    test "removes associated tier changes on deletion" do
      create(:billing_pending_subscription_item_change, subscribable: @published_tier)

      assert_difference "Billing::PendingSubscriptionItemChange.count", -1 do
        @published_tier.destroy
      end
    end

    test "has many billing transaction line items" do
      line_item = create(:billing_transaction_line_item, subscribable: @published_tier)

      assert_includes @published_tier.reload.billing_transaction_line_items, line_item
    end
  end

  context "#line_item_description" do
    test "includes listing slug and price for recurring tier when no invoice item is given" do
      assert_equal "#{@published_tier_listing.slug} - #{@published_tier.name}",
        @published_tier.line_item_description
    end

    test "includes listing slug and price for recurring tier when a non-fee invoice item is given" do
      invoice_item = Billing::Zuora::SubscribableInvoiceItem.new({
        "unitPrice" => @published_tier.monthly_price_in_dollars,
        "chargeName" => @published_tier_listing.monthly_plan_or_charge_name,
        "chargeAmount" => @published_tier.monthly_price_in_dollars,
        "quantity" => 1.0,
        "serviceStartDate" => "2022-09-22",
        "serviceEndDate" => "2022-10-21",
      }, subscribable: @published_tier)
      expected = "#{@published_tier_listing.slug} - #{@published_tier.name}"

      assert_equal expected, @published_tier.line_item_description(invoice_item: invoice_item)
    end

    test "includes listing slug and price for recurring tier when a fee invoice item is given" do
      invoice_item = Billing::Zuora::SubscribableInvoiceItem.new({
        "unitPrice" => @published_tier.monthly_price_in_dollars,
        "chargeName" => SponsorsListing.fee_charge_name_for(@published_tier_listing.monthly_plan_or_charge_name),
        "chargeAmount" => 0.15,
        "quantity" => 1.0,
        "serviceStartDate" => "2022-09-22",
        "serviceEndDate" => "2022-10-21",
      }, subscribable: @published_tier)
      expected = "#{@published_tier_listing.slug} - #{@published_tier.name} - fee"

      assert_equal expected, @published_tier.line_item_description(invoice_item: invoice_item)
    end

    test "includes listing slug and price for one-time tier when no invoice item is given" do
      tier = create(:sponsors_tier, :published, :one_time,
        monthly_price_in_cents: 50_00)
      assert_equal "#{tier.sponsors_listing.slug} - $50 one time", tier.line_item_description
    end

    test "includes listing slug and price for one-time tier when a non-fee invoice item is given" do
      one_time_tier = create(:sponsors_tier, :one_time, sponsors_listing: @listing)
      invoice_item = Billing::Zuora::SubscribableInvoiceItem.new({
        "unitPrice" => one_time_tier.monthly_price_in_dollars,
        "chargeName" => @listing.monthly_plan_or_charge_name,
        "chargeAmount" => one_time_tier.monthly_price_in_dollars,
        "quantity" => 1.0,
        "serviceStartDate" => "2022-09-22",
        "serviceEndDate" => "2022-10-21",
      }, subscribable: one_time_tier)
      expected = "#{@listing.slug} - #{one_time_tier.name}"

      assert_equal expected, one_time_tier.line_item_description(invoice_item: invoice_item)
    end

    test "includes listing slug and price for one-time tier when a fee invoice item is given" do
      one_time_tier = create(:sponsors_tier, :one_time, sponsors_listing: @listing)
      invoice_item = Billing::Zuora::SubscribableInvoiceItem.new({
        "unitPrice" => one_time_tier.monthly_price_in_dollars,
        "chargeName" => SponsorsListing.fee_charge_name_for(@listing.monthly_plan_or_charge_name),
        "chargeAmount" => 0.35,
        "quantity" => 1.0,
        "serviceStartDate" => "2022-09-22",
        "serviceEndDate" => "2022-10-21",
      }, subscribable: one_time_tier)
      expected = "#{@listing.slug} - #{one_time_tier.name} - fee"

      assert_equal expected, one_time_tier.line_item_description(invoice_item: invoice_item)
    end
  end

  context  "#billing_cycle" do
    test "is :one_time for one_time tiers" do
      tier = SponsorsTier.new(monthly_price_in_cents: 15_00, frequency: :one_time)
      assert_equal :one_time, tier.billing_cycle
    end

    test "is nil for recurring tiers" do
      tier = SponsorsTier.new(monthly_price_in_cents: 15_00, frequency: :recurring)
      assert_nil tier.billing_cycle
    end
  end

  context "#generate_name" do
    test "name is based on monthly cost and frequency" do
      tier = SponsorsTier.new(monthly_price_in_cents: 15_00, frequency: :one_time)
      assert_equal "$15 one time", tier.generate_name

      tier.frequency = :recurring
      assert_equal "$15 a month", tier.generate_name
    end

    test "name is based on yearly cost for invoiced sponsorships" do
      tier = SponsorsTier.new(
        state: :invoiced,
        frequency: :one_time,
        monthly_price_in_cents: 100_00,
        yearly_price_in_cents: 200_00,
      )

      assert_equal "$200 one time", tier.generate_name
    end
  end

  context "#generate_name_for" do
    test "returns an English-readable form of the tier price and frequency" do
      assert_equal "$10 a month", SponsorsTier.generate_name_for(10_00, :recurring)
      assert_equal "$250 one time", SponsorsTier.generate_name_for(250_00, :one_time)
    end
  end

  context "validations" do
    test "requires a Sponsors listing" do
      tier = build(:sponsors_tier, sponsors_listing: nil)

      refute_predicate tier, :valid?
      assert_includes tier.errors[:sponsors_listing], "must exist"
    end

    test "requires repository_id to point to a repository that exists" do
      invalid_id = (Repository.maximum(:id) || 1) + 100

      tier = build(:sponsors_tier, sponsorable: @sponsorable, repository_id: invalid_id)

      refute_predicate tier, :valid?
      assert_includes tier.errors[:repository], "can't be blank"
    end

    test "requires recurring tier if setting a repository" do
      org_sponsorable = create(:organization, :sponsorable)
      repo = create(:private_repository, owner: org_sponsorable)

      tier = build(:sponsors_tier, :one_time, sponsors_listing: org_sponsorable.sponsors_listing, repository: repo)

      refute_predicate tier, :valid?
      assert_includes tier.errors[:repository], "can only be specified for recurring tiers"
    end

    test "requires non-custom tier if setting a repository" do
      org_sponsorable = create(:organization, :sponsorable)
      repo = create(:private_repository, owner: org_sponsorable)

      tier = build(:sponsors_tier, :custom, sponsors_listing: org_sponsorable.sponsors_listing, repository: repo)

      refute_predicate tier, :valid?
      assert_includes tier.errors[:repository], "cannot be specified for custom tiers"
    end

    test "does not require a repository when require_repository is false" do
      org_listing = create(:sponsors_listing, :for_org)
      tier = build(:sponsors_tier, sponsors_listing: org_listing, repository_id: nil)
      assert_predicate tier, :valid?
    end

    test "requires a repository when require_repository is true" do
      org_listing = create(:sponsors_listing, :for_org)
      tier = build(:sponsors_tier, sponsors_listing: org_listing, repository_id: nil, require_repository: true)
      refute_predicate tier, :valid?
      assert_includes tier.errors[:repository], "can't be blank"
    end

    [:name, :monthly_price_in_cents, :yearly_price_in_cents].each do |attr|
      test "require #{attr}" do
        tier = build(:sponsors_tier, attr => nil)

        refute_predicate tier, :valid?
        assert_includes tier.errors[attr], "can't be blank"
      end
    end

    test "requires non-blank description for draft tier" do
      tier = build(:sponsors_tier, state: :draft, description: "")
      refute_predicate tier, :valid?
      assert_includes tier.errors[:description], "can't be blank"
    end

    test "requires non-blank description for published tier" do
      tier = build(:sponsors_tier, state: :published, description: "")
      refute_predicate tier, :valid?
      assert_includes tier.errors[:description], "can't be blank"
    end

    test "requires non-blank description for retired tier" do
      tier = build(:sponsors_tier, state: :retired, description: "")
      refute_predicate tier, :valid?
      assert_includes tier.errors[:description], "can't be blank"
    end

    test "requires parent tier be for the same Sponsors listing" do
      other_listing = create(:sponsors_listing)
      tier = SponsorsTier.new(sponsors_listing: other_listing, parent_tier: @published_tier)
      refute_predicate tier, :valid?
      assert_includes tier.errors[:parent_tier], "is for another Sponsors listing, " \
        "#{@published_tier.sponsorable_login} instead of #{other_listing.sponsorable_login}"
    end

    test "requires a tier not be its own parent" do
      tier = create(:sponsors_tier, :custom)
      tier.parent_tier = tier
      refute_predicate tier, :valid?
      assert_includes tier.errors[:parent_tier], "cannot be itself"
    end

    test "requires parent tier to be published at creation time" do
      tier = SponsorsTier.new(parent_tier: @draft_tier)
      refute_predicate tier, :valid?
      assert_includes tier.errors[:parent_tier], "must be published"
    end

    test "allows parent tier to not be published at update time" do
      published_tier = @listing.default_tier
      tier = create(:sponsors_tier, :custom, parent_tier: published_tier, sponsors_listing: @listing)
      retired_tier = create(:sponsors_tier, :retired, sponsors_listing: @listing,
        monthly_price_in_cents: tier.monthly_price_in_cents)
      tier.parent_tier = retired_tier
      assert_predicate tier, :valid?
    end

    test "disallows recurring parent tier for a one-time tier" do
      tier = SponsorsTier.new(frequency: :one_time, parent_tier: @published_tier)
      refute_predicate tier, :valid?
      assert_includes tier.errors[:parent_tier], "is a monthly tier instead of a one-time tier"
    end

    test "disallows one-time parent tier for a recurring tier" do
      one_time_tier = create(:sponsors_tier, :published, :one_time)
      tier = SponsorsTier.new(frequency: :recurring, parent_tier: one_time_tier)
      refute_predicate tier, :valid?
      assert_includes tier.errors[:parent_tier], "is a one-time tier instead of a monthly tier"
    end

    test "requires parent tier not to be specified for published tier" do
      tier = SponsorsTier.new(state: :published, parent_tier: @published_tier)
      refute_predicate tier, :valid?
      assert_includes tier.errors[:parent_tier], "cannot be set for a non-custom tier"
    end

    test "requires parent tier not to be specified for draft tier" do
      tier = SponsorsTier.new(state: :draft, parent_tier: @published_tier)
      refute_predicate tier, :valid?
      assert_includes tier.errors[:parent_tier], "cannot be set for a non-custom tier"
    end

    test "requires parent tier not to be specified for retired tier" do
      tier = SponsorsTier.new(state: :retired, parent_tier: @published_tier)
      refute_predicate tier, :valid?
      assert_includes tier.errors[:parent_tier], "cannot be set for a non-custom tier"
    end

    test "requires parent tier not to be specified for invoiced tier" do
      tier = SponsorsTier.new(state: :invoiced, parent_tier: @published_tier)
      refute_predicate tier, :valid?
      assert_includes tier.errors[:parent_tier], "cannot be set for a non-custom tier"
    end

    test "requires parent tier to have a lesser or equal value to the tier" do
      tier = SponsorsTier.new(state: :custom, parent_tier: @published_tier,
        monthly_price_in_cents: @published_tier.monthly_price_in_cents - 1_00)
      refute_predicate tier, :valid?
      assert_includes tier.errors[:parent_tier], "cannot exceed #{tier.formatted_monthly_price}"
    end

    test "allows blank description for custom tier" do
      tier = build(:sponsors_tier, :custom, description: "")
      assert_predicate tier, :valid?
    end

    test "allows blank description for invoiced tier" do
      tier = build(:sponsors_tier, :invoiced, description: "")
      assert_predicate tier, :valid?
    end

    test "requires non-nil description, even for for custom tier" do
      tier = build(:sponsors_tier, :custom, description: nil)
      refute_predicate tier, :valid?
      assert_includes tier.errors[:description], "can't be nil"
    end

    test "requires non-nil description, even for invoiced tier" do
      tier = build(:sponsors_tier, :invoiced, description: nil)
      refute_predicate tier, :valid?
      assert_includes tier.errors[:description], "can't be nil"
    end

    test "validates monthly price in cents is a whole-dollar amount" do
      tier = SponsorsTier.new(monthly_price_in_cents: 150) # $1.50
      refute_predicate tier, :valid?
      assert_includes tier.errors[:monthly_price_in_cents], "must be a whole-dollar amount (no cents)"
    end

    test "validates yearly price in cents is a whole-dollar amount" do
      tier = SponsorsTier.new(yearly_price_in_cents: 150) # $1.50
      refute_predicate tier, :valid?
      assert_includes tier.errors.full_messages, "Annual price must be a whole-dollar amount (no cents)"
    end

    test "validates name length" do
      text = "a" * (SponsorsTier::MAX_NAME_LENGTH + 1)
      tier = build(:sponsors_tier, name: text)

      refute_predicate tier, :valid?
      assert_includes tier.errors[:name], "is too long (maximum is 255 characters)"
    end

    test "requires creator on create" do
      tier = SponsorsTier.new(creator: nil)
      refute_predicate tier, :valid?
      assert_includes tier.errors[:creator], "can't be blank"
    end

    test "does not require creator on update for non-custom tiers" do
      tier = create(:sponsors_tier, :draft)
      tier.creator = nil
      assert_predicate tier, :valid?

      tier = create(:sponsors_tier, :published)
      tier.creator = nil
      assert_predicate tier, :valid?

      tier = create(:sponsors_tier, :retired)
      tier.creator = nil
      assert_predicate tier, :valid?
    end

    test "requires creator on update for custom tiers" do
      tier = create(:sponsors_tier, :custom)
      tier.creator = nil
      refute_predicate tier, :valid?
      assert_includes tier.errors[:creator], "can't be blank"
    end

    test "requires creator on update for invoiced tiers" do
      @invoiced_tier.creator = nil
      refute_predicate @invoiced_tier, :valid?
      assert_includes @invoiced_tier.errors[:creator], "can't be blank"
    end

    test "validates description length" do
      text = "a" * (SponsorsTier::MAX_DESCRIPTION_LENGTH + 1)
      tier = build(:sponsors_tier, description: text)

      refute_predicate tier, :valid?
      assert_includes tier.errors[:description], "is too long (maximum is 750 characters)"
    end

    test "validates invoiced tiers have one-time frequency" do
      assert_predicate @invoiced_tier, :invoiced?
      assert_predicate @invoiced_tier, :one_time?
      assert_predicate @invoiced_tier, :valid?

      @invoiced_tier.frequency = :recurring

      refute_predicate @invoiced_tier, :valid?
      assert_includes @invoiced_tier.errors[:frequency], "must be one-time for invoiced tiers"
    end

    context "#sponsors_only_repository_is_valid" do
      test "is valid when all conditions are met" do
        tier = build(:sponsors_tier, :with_repository)

        assert_predicate tier, :valid?
      end

      test "adds errors if the repository is invalid" do
        errors = ["some errors"]
        SponsorsTier::RepositoryValidator.any_instance.stubs(:errors).returns(errors)

        sponsorable = create(:user)
        repository = create(:repository, owner: sponsorable)
        tier = build(:sponsors_tier, repository: repository)

        refute_predicate tier, :valid?
        assert_equal tier.errors[:repository], errors
      end
    end

    context "#custom_amount_above_min" do
      test "validates custom amount above min" do
        min_in_cents = @custom_tier.monthly_price_in_cents + 1_00

        @custom_tier.sponsors_listing.update!(min_custom_tier_amount_in_cents: min_in_cents)

        assert_operator @custom_tier.monthly_price_in_cents, :<, min_in_cents

        refute_predicate @custom_tier, :valid?
        assert_includes @custom_tier.errors[:monthly_price_in_cents],
          "must be at least #{Billing::Money.new(min_in_cents).format(no_cents: true)}"
      end
    end

    test "validates numericality of monthly_price_in_cents" do
      tier = build(:sponsors_tier, monthly_price_in_cents: "dog")

      refute_predicate tier, :valid?
      assert_includes tier.errors[:monthly_price_in_cents], "is not a number"
    end

    test "validates numericality of yearly_price_in_cents" do
      tier = build(:sponsors_tier, yearly_price_in_cents: "dog")

      refute_predicate tier, :valid?
      assert_includes tier.errors[:yearly_price_in_cents], "is not a number"
    end

    test "validates monthly_price_in_cents is greater than 0" do
      negative_tier = build(:sponsors_tier, monthly_price_in_cents: -1)
      zero_tier = build(:sponsors_tier, monthly_price_in_cents: 0)

      refute_predicate negative_tier, :valid?
      assert_includes negative_tier.errors[:monthly_price_in_cents], "must be greater than 0"

      refute_predicate zero_tier, :valid?
      assert_includes zero_tier.errors[:monthly_price_in_cents], "must be greater than 0"
    end

    test "validates yearly_price_in_cents is greater than 0" do
      negative_tier = build(:sponsors_tier, yearly_price_in_cents: -1)
      zero_tier = build(:sponsors_tier, yearly_price_in_cents: 0)

      refute_predicate negative_tier, :valid?
      assert_includes negative_tier.errors[:yearly_price_in_cents], "must be greater than 0"

      refute_predicate zero_tier, :valid?
      assert_includes zero_tier.errors[:yearly_price_in_cents], "must be greater than 0"
    end

    test "validates name cannot be changed in published tier" do
      @published_tier.name = "new name"

      refute_predicate @published_tier, :valid?
      assert_includes @published_tier.errors[:name], "cannot be changed for a published tier"
    end

    test "validates name cannot be changed in retired tier" do
      @retired_tier.name = "new name"

      refute_predicate @retired_tier, :valid?
      assert_includes @retired_tier.errors[:name], "cannot be changed for a retired tier"
    end

    test "validates name cannot be changed in custom tier" do
      @custom_tier.name = "new name"

      refute_predicate @custom_tier, :valid?
      assert_includes @custom_tier.errors[:name], "cannot be changed for a custom tier"
    end

    test "validates name cannot be changed in invoiced tier" do
      @invoiced_tier.name = "new name"

      refute_predicate @invoiced_tier, :valid?
      assert_includes @invoiced_tier.errors[:name], "cannot be changed for a invoiced tier"
    end

    test "validates tier amount cannot be changed in published tier" do
      @published_tier.monthly_price_in_cents += 100
      @published_tier.yearly_price_in_cents += 100

      refute_predicate @published_tier, :valid?
      assert_includes @published_tier.errors[:monthly_price_in_cents],
        "cannot be changed for a published tier"
      assert_includes @published_tier.errors[:yearly_price_in_cents],
        "cannot be changed for a published tier"
    end

    test "validates tier amount cannot be changed in retired tier" do
      @retired_tier.monthly_price_in_cents += 100
      @retired_tier.yearly_price_in_cents += 100

      refute_predicate @retired_tier, :valid?
      assert_includes @retired_tier.errors[:monthly_price_in_cents],
        "cannot be changed for a retired tier"
      assert_includes @retired_tier.errors[:yearly_price_in_cents],
        "cannot be changed for a retired tier"
    end

    test "validates tier amount cannot be changed in custom tier" do
      @custom_tier.monthly_price_in_cents += 100
      @custom_tier.yearly_price_in_cents += 100

      refute_predicate @custom_tier, :valid?
      assert_includes @custom_tier.errors[:monthly_price_in_cents],
        "cannot be changed for a custom tier"
      assert_includes @custom_tier.errors[:yearly_price_in_cents],
        "cannot be changed for a custom tier"
    end

    test "validates tier amount cannot be changed in invoiced tier" do
      @invoiced_tier.monthly_price_in_cents += 100
      @invoiced_tier.yearly_price_in_cents += 100

      refute_predicate @invoiced_tier, :valid?
      assert_includes @invoiced_tier.errors[:monthly_price_in_cents],
        "cannot be changed for a invoiced tier"
      assert_includes @invoiced_tier.errors[:yearly_price_in_cents],
        "cannot be changed for a invoiced tier"
    end

    test "validates published tier count within limit per frequency" do
      limit = @listing.published_sponsors_tiers.recurring.count
      SponsorsTier.stub_const(:PUBLISHED_TIER_LIMIT_PER_FREQUENCY, limit) do
        tier = build(:sponsors_tier, :published, sponsors_listing: @listing)
        refute_predicate tier, :valid?
        assert_includes tier.errors[:sponsors_listing],
          "has reached its limit for published, monthly tiers"

        other_tier = build(:sponsors_tier, :published, :one_time, sponsors_listing: @listing)
        assert_predicate other_tier, :valid?, "should check limit per frequency"
      end
    end

    test "ignores non-published tiers when validating published tier count" do
      SponsorsTier.stub_const(:PUBLISHED_TIER_LIMIT_PER_FREQUENCY, @listing.sponsors_tiers.count + 1) do
        create(:sponsors_tier, :draft, sponsors_listing: @listing)
        create(:sponsors_tier, :retired, sponsors_listing: @listing)
        tier = build(:sponsors_tier, :published, sponsors_listing: @listing)

        assert_predicate tier, :valid?
      end
    end

    test "validates monthly tier amount is within limit" do
      tier = build(:sponsors_tier,
        monthly_price_in_cents: (SponsorsTier::MAX_SPONSORSHIP_AMOUNT_IN_DOLLARS + 1) * 100,
      )
      error_message = "exceeds maximum tier amount of $12,000"

      refute_predicate tier, :valid?
      assert_includes tier.errors[:monthly_price_in_cents], error_message
    end

    test "allows invoiced tiers to go beyond the monthly limit" do
      price = (SponsorsTier::MAX_SPONSORSHIP_AMOUNT_IN_DOLLARS + 1) * 100
      tier = build(:sponsors_tier, :invoiced, monthly_price_in_cents: price)

      assert_predicate tier, :valid?
    end

    test "allows non-invoiced tiers to go beyond the monthly limit when skip_max_amount_validation is true" do
      price = (SponsorsTier::MAX_SPONSORSHIP_AMOUNT_IN_DOLLARS + 1) * 100
      tier = build(:sponsors_tier, :skip_max_amount_validation, monthly_price_in_cents: price)

      assert_predicate tier, :valid?
    end

    test "validates published recurring tier amount is unique" do
      existing_tier = create(:sponsors_tier, :published, sponsors_listing: @listing, frequency: :recurring)
      tier = build(:sponsors_tier, sponsors_listing: @listing,
        monthly_price_in_cents: existing_tier.monthly_price_in_cents, frequency: :recurring)

      refute_predicate tier, :valid?
      assert_includes tier.errors.full_messages, "Monthly price #{existing_tier.formatted_monthly_price} is " \
        "already in use by a published, monthly tier"
    end

    test "validates published one-time tier amount is unique" do
      existing_tier = create(:sponsors_tier, :published, sponsors_listing: @listing, frequency: :one_time)
      tier = build(:sponsors_tier, sponsors_listing: @listing,
        monthly_price_in_cents: existing_tier.monthly_price_in_cents,
        frequency: :one_time
      )

      refute_predicate tier, :valid?
      assert_includes tier.errors[:monthly_price_in_cents],
        "#{existing_tier.formatted_monthly_price} is already in use by a published, one-time tier"
    end

    test "existing one-time tier does not prevent new recurring tier at same price" do
      existing_tier = create(:sponsors_tier, :published, frequency: :one_time)
      tier = build(:sponsors_tier, sponsors_listing: existing_tier.sponsors_listing,
        monthly_price_in_cents: existing_tier.monthly_price_in_cents,
        frequency: :recurring
      )

      assert_predicate tier, :valid?
    end

    test "existing recurring tier does not prevent new one-time tier at same price" do
      existing_tier = create(:sponsors_tier, :published, frequency: :recurring)
      tier = build(:sponsors_tier, sponsors_listing: existing_tier.sponsors_listing,
        monthly_price_in_cents: existing_tier.monthly_price_in_cents,
        frequency: :one_time
      )

      assert_predicate tier, :valid?
    end

    test "existing recurring tier does not prevent new one-time invoiced tier at same price" do
      existing_tier = create(:sponsors_tier, :published, frequency: :recurring)
      tier = build(:sponsors_tier, :invoiced,
        sponsors_listing: existing_tier.sponsors_listing,
        monthly_price_in_cents: existing_tier.monthly_price_in_cents,
      )

      assert_predicate tier, :valid?
    end

    test "validates custom tier amount is not the same as a published tier amount" do
      listing = @published_tier_listing
      tier = build(:sponsors_tier, :custom, sponsors_listing: listing,
        monthly_price_in_cents: @published_tier.monthly_price_in_cents)

      refute_predicate tier, :valid?
      assert_includes tier.errors[:monthly_price_in_cents],
        "#{@published_tier.formatted_monthly_price} is already in use by a published, monthly tier"
    end

    test "does not require unique tier amounts for already published tiers" do
      existing_tier = create(:sponsors_tier, :published, sponsors_listing: @listing)
      tier = build(:sponsors_tier,
        :published,
        sponsors_listing: @listing,
        monthly_price_in_cents: existing_tier.monthly_price_in_cents,
        name: "Some brand new tier"
      )

      result = tier.valid?
      assert result, tier.errors.full_messages.to_sentence
    end

    test "validates published tier name is unique, regardless of frequency" do
      existing_tier = create(:sponsors_tier, :published, sponsors_listing: @listing)
      tier = build(:sponsors_tier, :published, :one_time, sponsors_listing: @listing,
        name: existing_tier.name)

      refute_predicate tier, :valid?
      assert_includes tier.errors[:name], "is already in use by a published tier"
    end

    test "ignores retired tiers when validating tier name uniqueness" do
      existing_retired_tier = create(:sponsors_tier, :retired, sponsors_listing: @listing)
      retired_tier = create(:sponsors_tier,
        :retired,
        sponsors_listing: @listing,
        name: existing_retired_tier.name,
      )
      published_tier = create(:sponsors_tier,
        :published,
        name: existing_retired_tier.name,
      )

      assert_predicate retired_tier, :valid?
      assert_predicate published_tier, :valid?
    end
  end

  context "#actor_for_repository_invitation" do
    test "returns the sponsorable" do
      creator = create(:user)
      custom_tier = build(:sponsors_tier, :custom, sponsors_listing: @listing, creator: creator)
      assert_equal @sponsorable, custom_tier.actor_for_repository_invitation
    end
  end

  context "#create_sponsorship_repository" do
    test "creates a SponsorshipRepository when given user has a sponsorship using that tier" do
      tier_with_repo = create(:sponsors_tier, :approved_sponsors_listing, :with_repository)
      sponsorable = tier_with_repo.sponsorable
      sponsorship = create(:sponsorship, tier: tier_with_repo, sponsorable: sponsorable)
      sponsor = sponsorship.sponsor

      sponsorship_repo = assert_difference(-> { SponsorshipRepository.count }) do
        tier_with_repo.create_sponsorship_repository(sponsor: sponsor)
      end

      assert_instance_of SponsorshipRepository, sponsorship_repo
      assert_equal tier_with_repo, sponsorship_repo.sponsors_tier
      assert_equal sponsor, sponsorship_repo.sponsor
      assert_equal sponsorable, sponsorship_repo.sponsorable
      assert_equal tier_with_repo.repository, sponsorship_repo.repository
    end

    test "creates a SponsorshipRepository for repository granted by parent tier of a sponsorship's custom tier" do
      listing = create(:sponsors_listing, :approved)
      tier_with_repo = create(:sponsors_tier, :published, :with_repository, sponsors_listing: listing)
      custom_tier = create(:sponsors_tier, :custom, sponsors_listing: listing,
        parent_tier: tier_with_repo, monthly_price_in_cents: tier_with_repo.monthly_price_in_cents + 1_00)
      sponsor = custom_tier.creator
      sponsorable = tier_with_repo.sponsorable
      sponsorship = create(:sponsorship, tier: custom_tier, sponsorable: sponsorable, sponsor: sponsor)

      sponsorship_repo = assert_difference(-> { SponsorshipRepository.count }) do
        custom_tier.create_sponsorship_repository(sponsor: sponsor)
      end

      assert_instance_of SponsorshipRepository, sponsorship_repo
      assert_equal custom_tier, sponsorship_repo.sponsors_tier
      assert_equal sponsor, sponsorship_repo.sponsor
      assert_equal sponsorable, sponsorship_repo.sponsorable
      assert_equal tier_with_repo.repository, sponsorship_repo.repository
    end

    test "raises if SponsorshipRepository fails to save" do
      tier_with_repo = create(:sponsors_tier, :approved_sponsors_listing, :with_repository)

      assert_raises ActiveRecord::RecordInvalid do
        tier_with_repo.create_sponsorship_repository(sponsor: nil)
      end
    end
  end

  context ".with_states scope" do
    test "returns tiers scoped to a specific state" do
      tiers = SponsorsTier.with_states(:draft)

      assert_includes tiers, @draft_tier
      refute_includes tiers, @published_tier
    end

    test "returns tiers scoped to multiple states" do
      tiers = SponsorsTier.with_states(:draft, :published)

      assert_includes tiers, @draft_tier
      assert_includes tiers, @published_tier
      refute_includes tiers, @retired_tier
    end

    test "also works with strings" do
      tiers = SponsorsTier.with_states("draft", "retired")

      assert_includes tiers, @draft_tier
      assert_includes tiers, @retired_tier
      refute_includes tiers, @published_tier
    end

    test "ignores invalid states" do
      assert_empty SponsorsTier.with_states(:nonsense)
    end
  end

  context "last_billing_transaction_line_item relation" do
    test "returns latest line item for the tier" do
      line_item1 = travel_to(1.day.ago) do
        sponsorship1 = create(:sponsorship, tier: @published_tier)
        transaction1 = create(:billing_transaction, user: sponsorship1.sponsor,
          amount_in_cents: @published_tier.monthly_price_in_cents)
        create(:billing_transaction_line_item, billing_transaction: transaction1,
          subscribable: @published_tier, amount_in_cents: @published_tier.monthly_price_in_cents,
          quantity: 1, description: "GitHub Sponsors - #{sponsorship1.sponsorable} sponsorship")
      end

      assert_equal line_item1, @published_tier.last_billing_transaction_line_item

      sponsorship2 = create(:sponsorship, tier: @published_tier)
      transaction2 = create(:billing_transaction, user: sponsorship2.sponsor,
        amount_in_cents: @published_tier.monthly_price_in_cents)
      line_item2 = create(:billing_transaction_line_item, billing_transaction: transaction2,
        subscribable: @published_tier, amount_in_cents: @published_tier.monthly_price_in_cents,
        quantity: 2, description: "GitHub Sponsors - #{sponsorship2.sponsorable} sponsorship")

      assert_equal line_item2, @published_tier.reload.last_billing_transaction_line_item
    end
  end

  context "state transitions" do
    test "tier is draft by default" do
      tier = create(:sponsors_tier)
      assert_predicate tier, :draft?
    end

    test "transitions from draft to published when under tier limit for that frequency" do
      tier = create(:sponsors_tier)
      tier.publish!
      assert_predicate tier, :published?
    end

    test "does not transition from draft to published when at tier limit for recurring frequency" do
      limit = @listing.published_sponsors_tiers.recurring.count
      SponsorsTier.stub_const(:PUBLISHED_TIER_LIMIT_PER_FREQUENCY, limit) do
        tier = create(:sponsors_tier, :draft, sponsors_listing: @listing)
        assert_raises(Workflow::NoTransitionAllowed) { tier.publish! }
        refute_predicate tier, :published?
      end
    end

    test "does not transition from draft to published when at tier limit for one-time frequency" do
      limit = @listing.published_sponsors_tiers.one_time.count
      SponsorsTier.stub_const(:PUBLISHED_TIER_LIMIT_PER_FREQUENCY, limit) do
        tier = create(:sponsors_tier, :draft, :one_time, sponsors_listing: @listing)
        assert_raises(Workflow::NoTransitionAllowed) { tier.publish! }
        refute_predicate tier, :published?
      end
    end

    test "transitions from published to retired" do
      tier = create(:sponsors_tier, :published, sponsors_listing: @listing)
      tier.retire!
      assert_predicate tier, :retired?
    end

    test "transitions from published to retired even if no other published tiers left" do
      tier = @listing.default_tier
      tier.retire!
      assert_predicate tier, :retired?
    end

    test "does not transition from draft to retired" do
      tier = create(:sponsors_tier, :draft, sponsors_listing: @listing)
      assert_raises(Workflow::NoTransitionAllowed) { tier.retire! }
      refute_predicate tier, :retired?
    end
  end

  context "#pending_subscription_item_change and #async_pending_subscription_item_change" do
    test "returns pending cancellation" do
      tier = @published_tier
      pending_sub_item_change = create(:sponsors_pending_subscription_item_change,
        subscribable: tier,
        quantity: 0
      )
      account = pending_sub_item_change.pending_plan_change.user

      assert_equal pending_sub_item_change, tier.pending_subscription_item_change(account: account)
      assert_equal pending_sub_item_change, tier.async_pending_subscription_item_change(account: account).sync
    end

    test "returns pending change between tiers" do
      low_tier, high_tier = create_pair(:sponsors_tier, :published, sponsors_listing: @listing)
      pending_sub_item_change = create(:sponsors_pending_subscription_item_change, subscribable: low_tier)
      account = pending_sub_item_change.pending_plan_change.user

      assert_equal pending_sub_item_change, high_tier.pending_subscription_item_change(account: account)
      assert_equal pending_sub_item_change, high_tier.async_pending_subscription_item_change(account: account).sync
    end

    test "returns pending activation" do
      pending_sub_item_change = create(:sponsors_pending_subscription_item_change)
      tier = pending_sub_item_change.subscribable
      account = pending_sub_item_change.pending_plan_change.user

      assert_equal pending_sub_item_change, tier.pending_subscription_item_change(account: account)
      assert_equal pending_sub_item_change, tier.async_pending_subscription_item_change(account: account).sync
    end

    test "returns nil if no pending change exists" do
      user = create(:user)

      assert_nil @published_tier.pending_subscription_item_change(account: user)
      assert_nil @published_tier.async_pending_subscription_item_change(account: user).sync
    end

    test "returns pending cancellation for sponsors-invoiced organization" do
      account = create(:credit_card_org, :sponsors_invoiced)
      tier = @published_tier
      pending_plan_change = create(:billing_pending_plan_change,
        user: account
      )
      pending_sub_item_change = create(:sponsors_pending_subscription_item_change,
        pending_plan_change: pending_plan_change,
        subscribable: tier,
        quantity: 0
      )
      assert_predicate account, :sponsors_invoiced?

      assert_equal pending_sub_item_change, tier.pending_subscription_item_change(account: account)
      assert_equal pending_sub_item_change, tier.async_pending_subscription_item_change(account: account).sync
    end

    test "returns pending cancellation for enterprise account member org" do
      tier = @published_tier
      sub_item = create(:sponsors_subscription_item, :self_serve_business, subscribable: tier)
      business = sub_item.account
      pending_plan_change = create(:billing_pending_plan_change, :business,
        customer: business.customer
      )
      pending_sub_item_change = create(:sponsors_pending_subscription_item_change,
        pending_plan_change: pending_plan_change,
        subscribable: tier,
        organization: sub_item.organization,
        quantity: 0
      )
      other_member_org = create(:organization, business: business)

      assert_equal(
        pending_sub_item_change,
        tier.pending_subscription_item_change(account: business, organization: sub_item.organization)
      )
      assert_equal(
        pending_sub_item_change,
        tier.async_pending_subscription_item_change(account: business, organization: sub_item.organization).sync
      )
      # ensure we don't also consider this a change for another member org
      assert_nil tier.pending_subscription_item_change(account: business, organization: other_member_org)
      assert_nil tier.async_pending_subscription_item_change(account: business, organization: other_member_org).sync
    end

    test "async limits query count" do
      pending_plan_change = create(:billing_pending_plan_change)
      pending_sponsorship_changes = create_list(:sponsors_pending_subscription_item_change, 3,
        pending_plan_change: pending_plan_change
      )
      pending_marketplace_change = create(:billing_pending_subscription_item_change,
        pending_plan_change: pending_plan_change
      )
      tiers = pending_sponsorship_changes.map(&:subscribable)
      account = pending_plan_change.user

      change_promises = tiers.map { |tier| tier.async_pending_subscription_item_change(account: account) }
      assert_query_count_per_table({
        pending_plan_changes: 1,
        pending_subscription_item_changes: 1,
      }) do
        changes = Promise.all(change_promises).sync

        assert_equal pending_sponsorship_changes, changes
      end
    end
  end

  context "#prorated_total_price" do
    test "calculates prorated total for yearly plans" do
      Timecop.freeze("2018-02-16") do
        user = create(:user,
          plan_duration: User::BillingDependency::YEARLY_PLAN,
          billed_on: GitHub::Billing.today + 60.days,
        )
        sponsors_tier = create(:sponsors_tier,
          monthly_price_in_cents: 12_00,
          yearly_price_in_cents: 120_00,
        )

        # $12/month * (60/31) days = $23.22
        # Even though the user is on a yearly plan, prorated prices are
        # calculated on a monthly basis
        assert_money 23_22, sponsors_tier.prorated_total_price(account: user, quantity: 1)
      end
    end

    test "calculates a full period of service on the billing date, even when account has no plan subscription" do
      freeze_time do
        user = create(:user, plan_duration: User::BillingDependency::MONTHLY_PLAN, billed_on: GitHub::Billing.today)
        sponsors_tier = create(:sponsors_tier, monthly_price_in_cents: 12_00)

        assert_money 12_00, sponsors_tier.prorated_total_price(account: user, quantity: 1)
      end
    end
  end

  context "#description_html" do
    test "supports bulleted lists" do
      tier = build(:sponsors_tier, description: "- a nice tier")
      assert_match %r{<ul>\s+<li>a nice tier</li>\s+</ul>}, tier.description_html
    end

    test "supports task lists" do
      tier = build(:sponsors_tier, description: "- [ ] a nice tier")
      assert_match %r{<ul class=\"contains-task-list\">\s+<li class=\"task-list-item\"><input type=\"checkbox\" id=\"\" disabled=\"\" class=\"task-list-item-checkbox\"> a nice tier</li>\s+</ul>},
        tier.description_html
    end

    test "supports colon-style emoji" do
      tier = build(:sponsors_tier, description: ":smile:")
      doc = Nokogiri::HTML.fragment(tier.description_html)
      refute_nil doc.css("g-emoji[alias='smile']")
    end

    test "supports native emoji" do
      tier = build(:sponsors_tier, description: GRIN_EMOJI)
      doc = Nokogiri::HTML.fragment(tier.description_html)
      refute_nil doc.css("g-emoji[alias='smile']")
    end

    test "strips images" do
      tier = build(:sponsors_tier, description: "a nice tier ![image](/image.png)")
      assert_equal "<p>a nice tier </p>", tier.description_html
    end

    test "suppresses h1s, turning them into h2s" do
      tier = build(:sponsors_tier, description: "# a nice tier")
      assert_equal "<h2>a nice tier</h2>", tier.description_html
    end

    test "caches result till description changes" do
      with_cache_enabled do
        GitHub::Goomba::SponsorsTierDescriptionPipeline.expects(:to_html).once
          .returns("initial HTML result")
        tier = create(:sponsors_tier, description: "some description")
        assert_equal "initial HTML result", tier.description_html
        assert_equal "initial HTML result", tier.reload.description_html

        GitHub::Goomba::SponsorsTierDescriptionPipeline.expects(:to_html).once
          .returns("another HTML result")
        tier.update!(description: "some other value")
        assert_equal "another HTML result", tier.description_html
        assert_equal "another HTML result", tier.reload.description_html
      end
    end
  end

  context "#welcome_message=" do
    test "accepts emojis" do
      tier = create(:sponsors_tier, welcome_message: "🌈✨🌍")
      assert_equal "🌈✨🌍", tier.welcome_message
    end

    test "accepts special characters" do
      tier = create(:sponsors_tier, welcome_message: "mañana")
      assert_equal "mañana", tier.welcome_message
    end
  end

  context "#has_welcome_message?" do
    test "returns true when the tier has a welcome message" do
      welcome_message = "Hello world"
      tier = build(:sponsors_tier, welcome_message: welcome_message)
      assert_predicate tier, :has_welcome_message?
    end

    test "returns false when no welcome message is set" do
      assert_nil @published_tier.welcome_message, "need a tier without a welcome message"
      refute_predicate @published_tier, :has_welcome_message?
    end

    test "returns true when a custom tier's parent_tier has a welcome_message" do
      welcome_message = "Hello world"
      parent_tier = build(:sponsors_tier, welcome_message: welcome_message)
      child_tier = build(:sponsors_tier, :custom, parent_tier: parent_tier)
      assert_predicate child_tier, :has_welcome_message?
    end

    test "returns true when a custom tier's closest lesser value tier has a welcome message and parent_tier is not set" do
      welcome_message = "Hello world"
      @published_tier.update!(welcome_message: welcome_message)
      custom_tier = build(:sponsors_tier, :custom, parent_tier: nil,
        sponsors_listing: @published_tier_listing,
        monthly_price_in_cents: @published_tier.monthly_price_in_cents + 100)
      assert_predicate custom_tier, :has_welcome_message?
    end

    test "returns nil for custom tier without a parent tier" do
      custom_tier = build(:sponsors_tier, :custom, parent_tier: nil, welcome_message: nil)
      refute_predicate custom_tier, :has_welcome_message?
    end

    test "returns nil for custom tier with a parent tier who has no welcome message" do
      parent_tier = build(:sponsors_tier, welcome_message: nil)
      child_tier = build(:sponsors_tier, :custom, parent_tier: parent_tier, welcome_message: nil)
      assert_nil child_tier.welcome_message_markdown
    end
  end

  context "#welcome_message_markdown" do
    test "returns the tier's welcome_message" do
      welcome_message = "Hello world"
      tier = build(:sponsors_tier, welcome_message: welcome_message)
      assert_equal welcome_message, tier.welcome_message_markdown
    end

    test "returns a custom tier's parent_tier's welcome_message" do
      welcome_message = "Hello world"
      parent_tier = build(:sponsors_tier, welcome_message: welcome_message)
      child_tier = build(:sponsors_tier, :custom, parent_tier: parent_tier)
      assert_equal welcome_message, child_tier.welcome_message_markdown
    end

    test "returns a custom tier's closest lesser value tier's welcome_message when no parent_tier is set" do
      welcome_message = "Hello world"
      @published_tier.update!(welcome_message: welcome_message)
      custom_tier = build(:sponsors_tier, :custom, parent_tier: nil,
        sponsors_listing: @published_tier_listing,
        monthly_price_in_cents: @published_tier.monthly_price_in_cents + 100)
      assert_equal welcome_message, custom_tier.welcome_message_markdown
    end

    test "returns nil when no welcome message is set for a non-custom tier" do
      assert_nil @published_tier.welcome_message, "need a tier without a welcome message"
      refute_predicate @published_tier, :custom?, "need a non-custom tier"
      assert_nil @published_tier.welcome_message_markdown
    end

    test "returns nil for custom tier without a parent tier" do
      custom_tier = build(:sponsors_tier, :custom, parent_tier: nil, welcome_message: nil)
      assert_nil custom_tier.welcome_message_markdown
    end

    test "returns nil for custom tier with a parent tier who has no welcome message" do
      parent_tier = build(:sponsors_tier, welcome_message: nil)
      child_tier = build(:sponsors_tier, :custom, parent_tier: parent_tier, welcome_message: nil)
      assert_nil child_tier.welcome_message_markdown
    end
  end

  context "#welcome_message_html" do
    test "supports empty welcome messages" do
      tier = build(:sponsors_tier, welcome_message: nil)
      assert_equal "", tier.welcome_message_html
    end

    test "supports bulleted lists" do
      tier = build(:sponsors_tier, welcome_message: "- welcome new sponsor!")
      assert_match %r{<ul>\s+<li>welcome new sponsor!</li>\s+</ul>}, tier.welcome_message_html
    end

    test "supports colon-style emoji" do
      tier = build(:sponsors_tier, welcome_message: ":smile:")
      doc = Nokogiri::HTML.fragment(tier.welcome_message_html)
      refute_nil doc.css("g-emoji[alias='smile']")
    end

    test "supports native emoji" do
      tier = build(:sponsors_tier, welcome_message: GRIN_EMOJI)
      doc = Nokogiri::HTML.fragment(tier.welcome_message_html)
      refute_nil doc.css("g-emoji[alias='smile']")
    end

    test "uses closest tier's message if it has one and this tier is custom but has no parent_tier" do
      tier = create(:sponsors_tier,
        :approved_sponsors_listing,
        :published,
        welcome_message: "- welcome custom friend!",
      )

      listing = tier.sponsors_listing

      custom_tier = create(:sponsors_tier,
        :custom,
        sponsors_listing: listing,
        welcome_message: nil,
        parent_tier: nil,
        monthly_price_in_cents: tier.monthly_price_in_cents + 1_00,
      )

      assert_match %r{<ul>\s+<li>welcome custom friend!</li>\s+</ul>}, custom_tier.welcome_message_html
    end

    test "uses parent tier's message if it has one and this tier is custom" do
      parent_tier = create(:sponsors_tier,
        :approved_sponsors_listing,
        :published,
        welcome_message: "- welcome custom friend!",
      )

      listing = parent_tier.sponsors_listing

      custom_tier = create(:sponsors_tier,
        :custom,
        sponsors_listing: listing,
        welcome_message: nil,
        parent_tier: parent_tier,
        monthly_price_in_cents: parent_tier.monthly_price_in_cents + 1_00,
      )

      assert_match %r{<ul>\s+<li>welcome custom friend!</li>\s+</ul>}, custom_tier.welcome_message_html
    end
  end

  context "#async_description_readable_by?" do
    test "true for custom tier creator" do
      assert @custom_tier.async_description_readable_by?(@custom_tier.creator).sync
    end

    test "true for invoiced tier creator" do
      assert @invoiced_tier.async_description_readable_by?(@invoiced_tier.creator).sync
    end

    test "true for other org admins when sponsor is an organization" do
      org_admin1 = create(:user)
      org = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription),
        admin: org_admin1)
      org_admin2 = create(:user)
      org.add_admin(org_admin2)
      listing = create(:sponsors_listing, :approved)
      custom_tier = create(:sponsors_tier, :custom, sponsors_listing: listing,
        creator: org_admin1)
      create(:sponsorship, tier: custom_tier, sponsor: org,
        sponsorable: listing.sponsorable)

      assert custom_tier.async_description_readable_by?(org_admin2).sync
    end

    test "true for org admins for invoiced tiers when creator is an organization" do
      org = @invoiced_tier.creator
      admin = create(:user)
      org.add_admin(admin)

      assert @invoiced_tier.async_description_readable_by?(admin).sync
    end

    test "false for other org members when sponsor is an organization" do
      org_admin = create(:user)
      org = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription),
        admin: org_admin)
      org_member = create(:user)
      org.add_member(org_member)
      listing = create(:sponsors_listing, :approved)
      custom_tier = create(:sponsors_tier, :custom, sponsors_listing: listing,
        creator: org_admin)
      create(:sponsorship, tier: custom_tier, sponsor: org,
        sponsorable: listing.sponsorable)

      refute custom_tier.async_description_readable_by?(org_member).sync
    end

    test "false for org members for invoiced tiers when creator is an organization" do
      org = @invoiced_tier.creator
      member = create(:user)
      org.add_member(member)

      refute @invoiced_tier.async_description_readable_by?(member).sync
    end

    test "false for non-creator of custom tier" do
      rando = create(:user)
      refute @custom_tier.async_description_readable_by?(rando).sync

      sponsorable = @custom_tier.sponsorable
      refute @custom_tier.async_description_readable_by?(sponsorable).sync
    end

    test "false for non-creator of invoiced tier" do
      rando = create(:user)
      refute @invoiced_tier.async_description_readable_by?(rando).sync

      sponsorable = @invoiced_tier.sponsorable
      refute @invoiced_tier.async_description_readable_by?(sponsorable).sync
    end

    test "true for anyone for non-custom tier" do
      rando = create(:user)

      assert @published_tier.async_description_readable_by?(rando).sync
      assert @retired_tier.async_description_readable_by?(rando).sync
      assert @draft_tier.async_description_readable_by?(rando).sync
    end
  end

  context "#sponsorship_exists_for?" do
    test "false for nil actor" do
      refute @published_tier.sponsorship_exists_for?(nil)
    end

    test "true for sponsor subscribed to the tier" do
      sponsorship = create(:sponsorship, tier: @published_tier)
      assert @published_tier.sponsorship_exists_for?(sponsorship.sponsor)
    end

    test "true for given user who admins an org that's subscribed to the tier" do
      sponsorship = create(:sponsorship, :from_org, tier: @published_tier)
      org = sponsorship.sponsor
      assert @published_tier.sponsorship_exists_for?(org.admins.first)
    end

    test "false for given user who is subscribed to a different tier" do
      sponsorship = create(:sponsorship, tier: @custom_tier, sponsor: @custom_tier.creator)
      refute @published_tier.sponsorship_exists_for?(sponsorship.sponsor)
    end

    test "false for given user who has no sponsorships" do
      non_sponsor = create(:user)
      refute @published_tier.sponsorship_exists_for?(non_sponsor)
    end
  end

  context "#can_be_concurrent_with_subscription_item_for?" do
    test "returns true when given no other subscribable" do
      assert @published_tier.can_be_concurrent_with_subscription_item_for?(nil)
    end

    test "returns true when given a subscribable that isn't a Sponsors tier" do
      other_subscribable = create(:marketplace_listing_plan, :published)
      assert @published_tier.can_be_concurrent_with_subscription_item_for?(other_subscribable)
    end

    test "returns true when given a tier for another Sponsors listing" do
      other_tier = create(:sponsors_tier, :published)
      refute_equal other_tier.sponsors_listing, @published_tier_listing
      assert @published_tier.can_be_concurrent_with_subscription_item_for?(other_tier)
    end

    test "returns false when a one-time tier is given another one-time tier for the same listing" do
      one_time_tier1 = create(:sponsors_tier, :one_time, :published,
        sponsors_listing: @published_tier_listing)
      one_time_tier2 = create(:sponsors_tier, :one_time, :published,
        sponsors_listing: @published_tier_listing)

      refute one_time_tier1.can_be_concurrent_with_subscription_item_for?(one_time_tier2)
    end

    test "returns false when a recurring tier is given another recurring tier for the same listing" do
      other_recurring_tier = create(:sponsors_tier, :published, sponsors_listing: @published_tier_listing)
      refute @published_tier.can_be_concurrent_with_subscription_item_for?(other_recurring_tier)
    end

    test "returns true when a one-time tier is given a recurring tier for the same listing" do
      one_time_tier = create(:sponsors_tier, :one_time, :published,
        sponsors_listing: @published_tier_listing)

      assert one_time_tier.can_be_concurrent_with_subscription_item_for?(@published_tier)
    end

    test "returns true when a recurring tier is given a one-time tier for the same listing" do
      one_time_tier = create(:sponsors_tier, :one_time, :published,
        sponsors_listing: @published_tier_listing)

      assert @published_tier.can_be_concurrent_with_subscription_item_for?(one_time_tier)
    end
  end

  context "#parent_or_closest_lesser_value_tier" do
    test "returns parent tier when set" do
      tier_with_parent = build(:sponsors_tier, :custom)
      parent_tier = tier_with_parent.parent_tier
      refute_nil parent_tier
      assert_equal parent_tier, tier_with_parent.parent_or_closest_lesser_value_tier
    end

    test "returns closest lesser value tier when parent_tier is not set" do
      tier = build(:sponsors_tier, sponsors_listing: @published_tier_listing,
        monthly_price_in_cents: @published_tier.monthly_price_in_cents + 100, parent_tier: nil)
      assert_equal @published_tier, tier.parent_or_closest_lesser_value_tier
    end

    test "returns nil when parent_tier is not set and no tier of the same frequency exists with a lesser-or-equal price" do
      tier = build(:sponsors_tier, parent_tier: nil)
      assert_nil tier.closest_lesser_value_tier, "need a tier that has no closest lesser-value tier"
      assert_nil tier.parent_or_closest_lesser_value_tier
    end
  end

  context "#parent_or_closest_lesser_value_tier_repository" do
    test "returns parent tier's repository when set" do
      tier_with_parent = build(:sponsors_tier, :custom, parent_tier: @tier_with_repo)
      assert_equal @tier_with_repo.repository, tier_with_parent.parent_or_closest_lesser_value_tier_repository
    end

    test "returns nil when parent tier has no repository" do
      tier_with_parent = build(:sponsors_tier, :custom, parent_tier: @published_tier)
      assert_nil tier_with_parent.parent_or_closest_lesser_value_tier_repository
    end

    test "returns closest lesser-value tier's repository when parent_tier is not set" do
      tier = build(:sponsors_tier, :custom, sponsors_listing: @tier_with_repo.sponsors_listing,
        monthly_price_in_cents: @tier_with_repo.monthly_price_in_cents + 100, parent_tier: nil)
      assert_equal @tier_with_repo.repository, tier.parent_or_closest_lesser_value_tier_repository
    end

    test "returns nil when no parent tier is set and closest lesser-value tier has no repository" do
      tier = build(:sponsors_tier, :custom, sponsors_listing: @published_tier_listing,
        monthly_price_in_cents: @published_tier.monthly_price_in_cents + 100, parent_tier: nil)
      assert_nil tier.parent_or_closest_lesser_value_tier_repository
    end

    test "returns nil when parent_tier is not set and no tier of the same frequency exists with a lesser-or-equal price" do
      listing = create(:sponsors_listing, :approved, tier_count: 0)
      tier = build(:sponsors_tier, :custom, parent_tier: nil, sponsors_listing: listing)
      assert_nil tier.closest_lesser_value_tier, "need a tier that has no closest lesser-value tier"
      assert_nil tier.parent_or_closest_lesser_value_tier_repository
    end

    test "returns nil when parent tier has no repo even if a same-frequency tier with a lesser-or-equal price does have a repo" do
      parent_tier = build(:sponsors_tier, :published, sponsors_listing: @tier_with_repo.sponsors_listing,
        monthly_price_in_cents: @tier_with_repo.monthly_price_in_cents + 200, repository: nil)

      tier = build(:sponsors_tier, :custom, sponsors_listing: @tier_with_repo.sponsors_listing,
        monthly_price_in_cents: @tier_with_repo.monthly_price_in_cents + 100, parent_tier: parent_tier)
      assert_equal @tier_with_repo, tier.closest_lesser_value_tier,
        "need tier whose closest lesser-value tier does have a repo"

      assert_nil tier.parent_or_closest_lesser_value_tier_repository
    end
  end

  context "closest_lesser_value_tiers_for scope" do
    test "returns an empty result when no listing IDs are given" do
      assert_empty SponsorsTier.closest_lesser_value_tiers_for([], amounts: [], recurrings: [])
    end

    test "returns an empty result when given lists are of different sizes" do
      assert_empty SponsorsTier.closest_lesser_value_tiers_for([@listing.id], amounts: [], recurrings: [])
      assert_empty SponsorsTier.closest_lesser_value_tiers_for([@listing.id], amounts: [1], recurrings: [])
      assert_empty SponsorsTier.closest_lesser_value_tiers_for([@listing.id], amounts: [], recurrings: [true])
    end

    test "returns published tiers for the specified listings and recurrences, whose values are <= those given" do
      listing = create(:sponsors_listing, tier_count: 0)
      recurring_tier1 = create(:sponsors_tier, :published, sponsors_listing: listing,
        monthly_price_in_cents: 1_00)
      recurring_tier2 = create(:sponsors_tier, :published, sponsors_listing: listing,
        monthly_price_in_cents: 2_00)
      unpublished_recurring_tier3 = create(:sponsors_tier, sponsors_listing: listing,
        monthly_price_in_cents: 3_00) # unpublished, should not be returned
      recurring_tier5 = create(:sponsors_tier, :published, sponsors_listing: listing,
        monthly_price_in_cents: 5_00) # exceeds amount, should not be returned

      result = SponsorsTier.closest_lesser_value_tiers_for([listing.id], amounts: [4], recurrings: [true])
      assert_equal [recurring_tier2, recurring_tier1], result,
        "should have returned published recurring tiers <= $4 in order by price descending"

      unpublished_one_time_tier3 = create(:sponsors_tier, :one_time, sponsors_listing: listing,
        monthly_price_in_cents: 3_00) # unpublished, should not be returned
      one_time_tier3 = create(:sponsors_tier, :one_time, :published, sponsors_listing: listing,
        monthly_price_in_cents: 3_00)
      one_time_tier5 = create(:sponsors_tier, :one_time, :published, sponsors_listing: listing,
        monthly_price_in_cents: 5_00) # exceeds amount, should not be returned

      result = SponsorsTier.closest_lesser_value_tiers_for([listing.id, listing.id], amounts: [4, 4],
        recurrings: [true, false])
      assert_equal [one_time_tier3, recurring_tier2, recurring_tier1], result,
        "should have included published recurring and one-time tiers <= $4 in order by price descending"
    end
  end

  context "#closest_lesser_value_tier" do
    test "returns nil when there is no published tier of the same frequency with a lesser value" do
      @custom_tier.sponsors_listing.sponsors_tiers.destroy_all

      # Tier is for another listing
      create(:sponsors_tier, :published,
        monthly_price_in_cents: @custom_tier.monthly_price_in_cents - 1_00)

      # Tier is not published
      create(:sponsors_tier, :draft,
        sponsors_listing: @custom_tier.sponsors_listing,
        monthly_price_in_cents: @custom_tier.monthly_price_in_cents - 1_00)

      # Tier is for a different frequency
      create(:sponsors_tier, :published,
        frequency: :one_time,
        sponsors_listing: @custom_tier.sponsors_listing,
        monthly_price_in_cents: @custom_tier.monthly_price_in_cents - 1_00)

      assert_nil @custom_tier.closest_lesser_value_tier
    end

    test "returns closest published tier of same frequency with a lesser value" do
      lesser_by_1 = create(:sponsors_tier, :published,
        sponsors_listing: @custom_tier.sponsors_listing,
        monthly_price_in_cents: @custom_tier.monthly_price_in_cents - 1_00)
      assert_equal lesser_by_1, @custom_tier.closest_lesser_value_tier

      lesser_by_2 = create(:sponsors_tier, :published,
        sponsors_listing: @custom_tier.sponsors_listing,
        monthly_price_in_cents: @custom_tier.monthly_price_in_cents - 2_00)
      assert_equal lesser_by_1, @custom_tier.reload.closest_lesser_value_tier,
        "should still return the tier closest in value"
    end

    test "returns closest published tier of same frequency with an equal value" do
      equal_value_tier = create(:sponsors_tier, :published,
        sponsors_listing: @custom_tier.sponsors_listing,
        monthly_price_in_cents: @custom_tier.monthly_price_in_cents)

      assert_equal equal_value_tier, @custom_tier.closest_lesser_value_tier

      lesser_by_1 = create(:sponsors_tier, :published,
        sponsors_listing: @custom_tier.sponsors_listing,
        monthly_price_in_cents: @custom_tier.monthly_price_in_cents - 1_00)

      assert_equal equal_value_tier, @custom_tier.reload.closest_lesser_value_tier,
        "should still return the tier equal in value"

      lesser_by_2 = create(:sponsors_tier, :published,
        sponsors_listing: @custom_tier.sponsors_listing,
        monthly_price_in_cents: @custom_tier.monthly_price_in_cents - 2_00)

      assert_equal equal_value_tier, @custom_tier.reload.closest_lesser_value_tier,
      "should still return the tier equal in value"
    end

    test "works when called on a published recurring tier" do
      tier = create(:sponsors_tier, :published, monthly_price_in_cents: 3_00)
      listing = tier.sponsors_listing
      assert_equal [tier], listing.published_sponsors_tiers.recurring, "need a listing with no other recurring tiers"
      assert_nil tier.closest_lesser_value_tier, "should not return itself as its own closest lesser-value tier"

      lesser_value_tier = create(:sponsors_tier, :published, sponsors_listing: listing,
        monthly_price_in_cents: 1_00)
      assert_equal lesser_value_tier, tier.reload.closest_lesser_value_tier

      closer_lesser_value_tier = create(:sponsors_tier, :published, sponsors_listing: listing,
        monthly_price_in_cents: 2_00)
      assert_equal closer_lesser_value_tier, tier.reload.closest_lesser_value_tier
    end

    test "works when called on a published one-time tier" do
      tier = create(:sponsors_tier, :published, :one_time, monthly_price_in_cents: 3_00)
      listing = tier.sponsors_listing
      assert_equal [tier], listing.published_sponsors_tiers.one_time, "need a listing with no other one-time tiers"
      assert_nil tier.closest_lesser_value_tier, "should not return itself as its own closest lesser-value tier"

      lesser_value_tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: listing,
        monthly_price_in_cents: 1_00)
      assert_equal lesser_value_tier, tier.reload.closest_lesser_value_tier

      closer_lesser_value_tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: listing,
        monthly_price_in_cents: 2_00)
      assert_equal closer_lesser_value_tier, tier.reload.closest_lesser_value_tier
    end

    test "works on an unpersisted tier" do
      tier = build(:sponsors_tier, :custom, sponsors_listing: @published_tier_listing,
        monthly_price_in_cents: @published_tier.monthly_price_in_cents + 1_00, frequency: @published_tier.frequency)
      assert_equal @published_tier, tier.closest_lesser_value_tier
    end

    test "can be batch loaded" do
      recurring_tier2_for_listing1 = create(:sponsors_tier, :published, monthly_price_in_cents: 2_00)
      listing1 = recurring_tier2_for_listing1.sponsors_listing
      recurring_tier1_for_listing1 = create(:sponsors_tier, :published, monthly_price_in_cents: 1_00,
        sponsors_listing: listing1)
      one_time_tier1_for_listing1 = create(:sponsors_tier, :published, :one_time, monthly_price_in_cents: 1_00,
        sponsors_listing: listing1)
      one_time_tier2_for_listing1 = create(:sponsors_tier, :published, :one_time, monthly_price_in_cents: 2_00,
        sponsors_listing: listing1)

      recurring_tier1_for_listing2 = create(:sponsors_tier, :published, monthly_price_in_cents: 1_00)
      listing2 = recurring_tier1_for_listing2.sponsors_listing
      recurring_tier2_for_listing2 = create(:sponsors_tier, :published, monthly_price_in_cents: 2_00,
        sponsors_listing: listing2)

      tiers = [recurring_tier1_for_listing1, one_time_tier1_for_listing1, recurring_tier2_for_listing1,
        one_time_tier2_for_listing1, recurring_tier1_for_listing2, recurring_tier2_for_listing2]

      assert_query_count_per_table({ sponsors_tiers: 1 }) do
        GitHub::PrefillAssociations.prefill_batch_method(tiers, :closest_lesser_value_tier)
      end

      assert_query_count(0) do
        assert_equal recurring_tier1_for_listing1, recurring_tier2_for_listing1.closest_lesser_value_tier
        assert_nil recurring_tier1_for_listing1.closest_lesser_value_tier
        assert_equal one_time_tier1_for_listing1, one_time_tier2_for_listing1.closest_lesser_value_tier
        assert_nil one_time_tier1_for_listing1.closest_lesser_value_tier
        assert_equal recurring_tier1_for_listing2, recurring_tier2_for_listing2.closest_lesser_value_tier
        assert_nil recurring_tier1_for_listing2.closest_lesser_value_tier
      end
    end
  end

  context ".subscription_items_adminable_by?" do
    test "returns true when actor owns the account" do
      assert SponsorsTier.subscription_items_adminable_by?(sponsor: @sponsorable, actor: @sponsorable)
    end

    test "returns true when actor is an admin of the org" do
      sponsorable_org = create(:organization, :sponsorable)
      assert SponsorsTier.subscription_items_adminable_by?(sponsor: sponsorable_org, actor: sponsorable_org.admin)
    end

    test "returns true when actor is a billing manager of the org" do
      sponsorable_org = create(:organization, :sponsorable)
      billing_manager = create(:user)
      sponsorable_org.billing.add_manager(billing_manager, actor: sponsorable_org.admin)

      assert SponsorsTier.subscription_items_adminable_by?(sponsor: sponsorable_org, actor: billing_manager)
    end

    test "returns true for an invoiced org when actor is a staff member" do
      invoiced_org = create(:invoiced_organization, :sponsors_invoiced)
      staff = create(:staff_admin_user)

      assert invoiced_org.subscription_items_adminable_by?(staff, subscribable_type: "SponsorsTier")
    end

    test "returns false if sponsor or actor is nil" do
      refute SponsorsTier.subscription_items_adminable_by?(sponsor: nil, actor: nil)
      refute SponsorsTier.subscription_items_adminable_by?(sponsor: nil, actor: @sponsorable)
      refute SponsorsTier.subscription_items_adminable_by?(sponsor: @sponsorable, actor: nil)
    end

    test "returns false for a random actor" do
      user = create(:user)
      refute SponsorsTier.subscription_items_adminable_by?(sponsor: @sponsorable, actor: user)
    end

    test "returns false for a non-invoiced org when actor is a staff user" do
      non_invoiced_org = create(:organization, :sponsorable)
      staff = create(:staff_admin_user)

      refute SponsorsTier.subscription_items_adminable_by?(sponsor: non_invoiced_org, actor: staff)
    end
  end

  context ".closest_lesser_value_tier_for" do
    test "returns nil when there is no published tier of the same frequency with a lesser value" do
      @custom_tier.sponsors_listing.published_sponsors_tiers.destroy_all
      amount = @custom_tier.monthly_price_in_dollars.to_i
      listing_id = @custom_tier.sponsors_listing_id

      # Tier is for another listing
      create(:sponsors_tier, :published,
        monthly_price_in_cents: (amount - 1) * 100)

      # Tier is not published
      create(:sponsors_tier, :draft, sponsors_listing_id: listing_id,
        monthly_price_in_cents: (amount - 1) * 100)

      # Tier is for a different frequency
      create(:sponsors_tier, :published, :one_time, sponsors_listing_id: listing_id,
        monthly_price_in_cents: (amount - 1) * 100)

      assert_nil SponsorsTier.closest_lesser_value_tier_for(listing_id, amount: amount, is_recurring: true)
    end

    test "returns closest published tier of same frequency with a lesser value for specified Sponsors listing" do
      amount = @custom_tier.monthly_price_in_dollars.to_i
      listing_id = @custom_tier.sponsors_listing_id

      lesser_by_1 = create(:sponsors_tier, :published,
        sponsors_listing: @custom_tier.sponsors_listing,
        monthly_price_in_cents: (amount - 1) * 100)
      assert_equal lesser_by_1, SponsorsTier.closest_lesser_value_tier_for(listing_id, amount: amount,
        is_recurring: true)

      lesser_by_2 = create(:sponsors_tier, :published,
        sponsors_listing: @custom_tier.sponsors_listing,
        monthly_price_in_cents: (amount - 2) * 100)
      assert_equal lesser_by_1, SponsorsTier.closest_lesser_value_tier_for(listing_id, amount: amount,
        is_recurring: true), "should still return the tier closest in value"
    end

    test "returns closest published tier of same frequency with an equal value for specified Sponsors listing" do
      amount = 50
      custom_one_time_tier = create(:sponsors_tier, :approved_sponsors_listing, :one_time, :custom,
        monthly_price_in_cents: amount * 100)
      listing_id = custom_one_time_tier.sponsors_listing_id

      equal_value_tier = create(:sponsors_tier, :published, :one_time, sponsors_listing_id: listing_id,
        monthly_price_in_cents: custom_one_time_tier.monthly_price_in_cents)
      assert_equal equal_value_tier, SponsorsTier.closest_lesser_value_tier_for(listing_id, amount: amount,
        is_recurring: false)

      lesser_by_1 = create(:sponsors_tier, :published, :one_time, sponsors_listing_id: listing_id,
        monthly_price_in_cents: custom_one_time_tier.monthly_price_in_cents - 1_00)
      assert_equal equal_value_tier, SponsorsTier.closest_lesser_value_tier_for(listing_id, amount: amount,
        is_recurring: false), "should still return the tier equal in value"
    end
  end

  context "#readable_by? and #async_readable_by? and visible_to scope" do
    test "true for org admin for active sponsorship on retired tier" do
      sponsorship = create(:sponsorship, :from_org)
      admin = sponsorship.sponsor.admin
      tier = sponsorship.tier
      tier.retire!

      assert_tier_readable_by(tier, admin)
    end

    test "true for org admin for active sponsorship on custom tier" do
      custom_tier = create(:sponsors_tier, :custom)
      sponsorship = create(:sponsorship, :from_org, tier: custom_tier)
      org = sponsorship.sponsor
      admin = org.admins.first

      assert_tier_readable_by(custom_tier, admin)
    end

    test "true for org admin on invoiced tier" do
      admin = create(:user)
      @invoiced_tier.creator.add_admin(admin)

      assert_tier_readable_by(@invoiced_tier, admin)
    end

    test "true for org admin for inactive sponsorship on retired tier" do
      sponsorship = create(:sponsorship, :inactive, :from_org)
      org = sponsorship.sponsor
      admin = org.admins.first
      tier = sponsorship.tier
      tier.retire!

      assert_tier_readable_by(tier, admin)
    end

    test "true for org admin for inactive subscription on custom tier" do
      custom_tier = create(:sponsors_tier, :custom)
      sponsorship = create(:sponsorship, :inactive, :from_org, tier: custom_tier)
      org = sponsorship.sponsor
      admin = org.admins.first

      assert_tier_readable_by(custom_tier, admin)
    end

    test "false for org member for subscription on retired tier" do
      subscription_item = create(:sponsors_subscription_item, :org)
      org = subscription_item.plan_subscription.user
      member = create(:user)
      org.add_member(member)
      tier = subscription_item.subscribable
      tier.retire!

      refute_tier_readable_by(tier, member)
    end

    test "false for org member for subscription on custom tier" do
      custom_tier = create(:sponsors_tier, :custom)
      subscription_item = create(:sponsors_subscription_item, :org, subscribable: custom_tier)
      org = subscription_item.plan_subscription.user
      member = create(:user)
      org.add_member(member)

      refute_tier_readable_by(custom_tier, member)
    end

    test "false for org member on invoiced tier" do
      member = create(:user)
      @invoiced_tier.creator.add_member(member)

      refute_tier_readable_by(@invoiced_tier, member)
    end

    test "true for sponsorable viewing their own draft tier" do
      listing = create(:sponsors_listing, :draft)
      tier = create(:sponsors_tier, :draft, listing: listing)

      assert_tier_readable_by(tier, listing.sponsorable)
    end

    test "true for sponsor viewing their own custom tier" do
      custom_tier = create(:sponsors_tier, :custom)
      sponsor = custom_tier.creator
      plan_subscription = sponsor.sponsors_plan_subscription || sponsor.plan_subscription
      subscription_item = create(:sponsors_subscription_item, subscribable: custom_tier,
        account: sponsor)

      assert_tier_readable_by(custom_tier, sponsor)
    end

    test "true for sponsorable viewing a custom tier for their listing" do
      custom_tier = create(:sponsors_tier, :custom)
      assert_tier_readable_by(custom_tier, custom_tier.sponsorable)
    end

    test "true for sponsorable viewing an invoiced tier for their listing" do
      listing = @invoiced_tier.sponsors_listing
      assert_tier_readable_by(@invoiced_tier, listing.sponsorable)
    end

    test "true for nil viewer if tier is published and listing is approved" do
      tier = create(:sponsors_tier, :published, listing: @listing)
      assert_predicate tier.listing, :approved?

      assert_tier_readable_by(tier, nil)
    end

    test "false for nil viewer if tier is published but listing is not approved" do
      listing = create(:sponsors_listing, :draft)
      tier = create(:sponsors_tier, :published, listing: listing)

      refute_tier_readable_by(tier, nil)
    end

    test "false for nil viewer if tier is custom" do
      custom_tier = create(:sponsors_tier, :custom)
      assert_predicate custom_tier.listing, :approved?

      refute_tier_readable_by(custom_tier, nil)
    end

    test "false for nil viewer if tier is invoiced" do
      refute_tier_readable_by(@invoiced_tier, nil)
    end
  end

  def assert_tier_readable_by(tier, user)
    tier_desc = "#{tier.current_state_name} #{tier}"
    user_desc = user ? "viewer #{user}" : "anonymous viewer"
    assert tier.readable_by?(user), "expected #readable_by? to return true for #{tier_desc} with #{user_desc}"
    assert tier.async_readable_by?(user).sync,
      "expected #async_readable_by? to agree with #readable_by? for #{tier_desc} with #{user_desc} (true)"
    assert_equal [tier], SponsorsTier.visible_to(user).where(id: tier.id),
      "expected visible_to scope to include #{tier_desc} for #{user_desc} to match #readable_by? result"
  end

  def refute_tier_readable_by(tier, user)
    tier_desc = "#{tier.current_state_name} #{tier}"
    user_desc = user ? "viewer #{user}" : "anonymous viewer"
    refute tier.readable_by?(user), "expected #readable_by? to return false for #{tier_desc} with #{user_desc}"
    refute tier.async_readable_by?(user).sync,
      "expected #async_readable_by? to agree with #readable_by? for #{tier_desc} with #{user_desc} (false)"
    assert_empty SponsorsTier.visible_to(user).where(id: tier.id),
      "expected visible_to scope to omit #{tier_desc} for #{user_desc} to match #readable_by? result"
  end

  # See also tests above for visible_to that ensure the result stays consistent with #readable_by?
  # and #async_readable_by?.
  context "visible_to scope" do
    test "only returns each tier once" do
      sponsorship1, _ = create_pair(:sponsorship, tier: @published_tier)
      sponsor = sponsorship1.sponsor
      assert_equal [@published_tier], SponsorsTier.visible_to(sponsor).where(id: @published_tier.id).to_a
    end
  end

  context "#adminable_by?" do
    test "returns false if actor is a rando" do
      user = create(:user)
      refute @draft_tier.adminable_by?(user)
    end

    test "returns true if tier's listing is adminable by the actor" do
      user = @draft_tier.sponsorable
      assert @draft_tier.adminable_by?(user)
    end
  end

  context "#editable_by?" do
    test "returns false for unrelated user if tier is retired" do
      rando = create(:user)
      refute @retired_tier.editable_by?(rando)
    end

    test "returns false for sponsorable if tier is retired" do
      sponsorable = @retired_tier.sponsorable
      refute @retired_tier.editable_by?(sponsorable)
    end

    test "returns false for unrelated user if tier is custom" do
      rando = create(:user)
      refute @custom_tier.editable_by?(rando)
    end

    test "returns false for unrelated user if tier is invoiced" do
      rando = create(:user)
      refute @invoiced_tier.editable_by?(rando)
    end

    test "returns false for sponsorable if tier is custom" do
      sponsorable = @custom_tier.sponsorable
      refute @custom_tier.editable_by?(sponsorable)
    end

    test "returns false for sponsorable if tier is invoiced" do
      sponsorable = @invoiced_tier.sponsorable
      refute @invoiced_tier.editable_by?(sponsorable)
    end

    test "returns false for org sponsor if tier is custom" do
      org_sponsor = create(:sponsors_subscription_item, :org, subscribable: @custom_tier)
        .plan_subscription.user
      refute @custom_tier.editable_by?(org_sponsor)
    end

    test "returns true for creator if tier is custom" do
      assert @custom_tier.editable_by?(@custom_tier.creator)
    end

    test "returns true for creator if tier is invoiced" do
      assert @invoiced_tier.editable_by?(@invoiced_tier.creator)
    end

    test "returns true for other org admin if tier is custom and sponsor is an org" do
      sponsorship = create(:sponsorship, :from_org, tier: @custom_tier)
      org_sponsor = sponsorship.sponsor
      org_admin = org_sponsor.admin

      assert @custom_tier.editable_by?(org_admin)
    end

    test "returns true for org admin if tier is invoiced" do
      admin = create(:user)
      @invoiced_tier.creator.add_admin(admin)

      assert @invoiced_tier.editable_by?(admin)
    end

    test "returns false for unrelated user if tier is draft" do
      rando = create(:user)
      refute @draft_tier.editable_by?(rando)
    end

    test "returns true for sponsorable if tier is draft" do
      sponsorable = @draft_tier.sponsorable
      assert @draft_tier.editable_by?(sponsorable)
    end

    test "returns false for unrelated user if tier is published" do
      rando = create(:user)
      refute @published_tier.editable_by?(rando)
    end

    test "returns true for sponsorable if tier is published" do
      sponsorable = @published_tier.sponsorable
      assert @published_tier.editable_by?(sponsorable)
    end

    test "returns false for sponsor if tier is published" do
      sponsor = create(:sponsors_subscription_item, subscribable: @published_tier)
        .plan_subscription.user
      refute @published_tier.editable_by?(sponsor)
    end
  end

  context "#grants_repository_access_to?" do
    test "returns false for organization sponsor" do
      org = build(:organization)
      refute @tier_with_repo.grants_repository_access_to?(org)
    end

    test "returns true for user sponsor when tier has a repository" do
      user = build(:user)
      assert @tier_with_repo.grants_repository_access_to?(user)
    end

    test "returns true for user sponsor when tier has a parent tier with a repository" do
      user = build(:user)
      child_tier = build(:sponsors_tier, :published, :custom, sponsors_listing: @tier_with_repo.sponsors_listing,
        parent_tier: @tier_with_repo)
      assert child_tier.grants_repository_access_to?(user)
    end

    test "returns false for user sponsor when tier does not have a repository" do
      refute_predicate @published_tier, :has_repository?, "need a tier that doesn't have a repository"

      user = build(:user)
      refute @published_tier.grants_repository_access_to?(user)
    end
  end

  context "#deletable_by?" do
    test "returns true if tier is draft" do
      user = @draft_tier.sponsorable
      assert @draft_tier.deletable_by?(user)
    end

    test "returns false if actor is a rando" do
      user = create(:user)
      refute @draft_tier.deletable_by?(user)
    end

    test "returns true if tier is published but its listing is not approved" do
      unapproved_listing = create(:sponsors_listing)
      published_tier = create(:sponsors_tier, :published, sponsors_listing: unapproved_listing)
      assert published_tier.deletable_by?(unapproved_listing.sponsorable)
    end

    test "returns false if tier is published and its listing is approved" do
      published_tier = create(:sponsors_tier, :published, sponsors_listing: @listing)
      refute published_tier.deletable_by?(@sponsorable)
    end

    test "returns false if tier is retired and its listing is approved" do
      retired_tier = create(:sponsors_tier, :retired, sponsors_listing: @listing)
      refute retired_tier.deletable_by?(@sponsorable)
    end
  end

  context "#can_publish?" do
    test "true for draft tier when listing not at max tier count" do
      assert_predicate @draft_tier, :can_publish?
    end

    test "false for draft tier when listing at max tier count" do
      SponsorsTier.stub_const(:PUBLISHED_TIER_LIMIT_PER_FREQUENCY, 1) do
        create(:sponsors_tier, :published, sponsors_listing: @draft_tier.sponsors_listing)
        refute_predicate @draft_tier, :can_publish?
      end
    end

    test "false for published tier" do
      refute_predicate @published_tier, :can_publish?
    end

    test "false for retired tier" do
      refute_predicate @retired_tier, :can_publish?
    end
  end

  context "#can_change_pricing?" do
    test "true for draft tiers" do
      tier = create(:sponsors_tier, :draft)

      assert_predicate tier, :can_change_pricing?
    end

    test "false for published tiers with no subscriptions" do
      tier = create(:sponsors_tier, :published)

      refute_predicate tier, :can_change_pricing?
    end

    test "false for published tiers with subscriptions" do
      tier = create(:sponsors_tier, :published)
      create(:sponsors_subscription_item, subscribable: tier)

      refute_predicate tier, :can_change_pricing?
    end
  end

  context "#base_price" do
    test "returns the price including fees when include_fees is true" do
      org = create(:credit_card_org)

      tier = create(:sponsors_tier, :published, monthly_price_in_cents: 100)
      sub_item = create(:sponsors_subscription_item, subscribable: tier, account: org)

      assert_equal Billing::Money.new(106), tier.base_price(include_fees: true, subscription_item: sub_item)
    end

    test "returns the price excluding fees when include_fees is false" do
      org = create(:credit_card_org)

      tier = create(:sponsors_tier, :published, monthly_price_in_cents: 100)
      sub_item = create(:sponsors_subscription_item, subscribable: tier, account: org)

      assert_equal Billing::Money.new(100), tier.base_price(include_fees: false, subscription_item: sub_item)
    end

    test "returns yearly price including fees" do
      org = create(:credit_card_org, plan_duration: "year")

      tier = create(:sponsors_tier, :published, monthly_price_in_cents: 100)
      sub_item = create(:sponsors_subscription_item, subscribable: tier, account: org)

      assert_equal Billing::Money.new(1272), tier.base_price(duration: :year, include_fees: true, subscription_item: sub_item)
    end

    test "returns yearly price excluding fees" do
      org = create(:credit_card_org, plan_duration: "year")

      tier = create(:sponsors_tier, :published, monthly_price_in_cents: 100)
      sub_item = create(:sponsors_subscription_item, subscribable: tier, account: org)

      assert_equal Billing::Money.new(1200), tier.base_price(duration: :year, include_fees: false)
    end

    test "raises error if subscription item is not provided when include_fees is true" do
      org = create(:credit_card_org)

      tier = create(:sponsors_tier, :published, monthly_price_in_cents: 100)
      sub_item = create(:sponsors_subscription_item, subscribable: tier, account: org)

      error = assert_raises do
        tier.base_price(include_fees: true)
      end
      assert_match /Need a subscription item to determine the fee/, error.message
    end
  end

  context "#subscription_items" do
    test "returns subscription items associated with this tier" do
      item = create :sponsors_subscription_item, subscribable: @published_tier
      other_tier = create :sponsors_tier, :published,
        sponsors_listing: @published_tier_listing
      other_item = create :sponsors_subscription_item, subscribable: other_tier

      assert_includes @published_tier.subscription_items, item
      assert_equal 1, @published_tier.subscription_items.count
    end
  end

  context "target_for_conditional_access" do
    test "tfca defers to sponsors listing" do
      assert_equal @published_tier_listing.target_for_conditional_access, @published_tier.target_for_conditional_access
    end

    test "async_tfca defers to sponsors listing" do
      assert_equal @published_tier_listing.target_for_conditional_access, @published_tier.async_target_for_conditional_access.sync
    end
  end

  context "#equal_price?" do
    test "returns true for equally priced SponsorsTier and SponsorsPatreonTier" do
      sponsors_tier = SponsorsTier.new(monthly_price_in_cents: 1_00, yearly_price_in_cents: 12_00)
      patreon_tier = SponsorsPatreonTier.new(amount_in_cents: 1_00)
      assert sponsors_tier.equal_price?(patreon_tier)
    end

    test "returns false for differently priced SponsorsTier and SponsorsPatreonTier" do
      sponsors_tier = SponsorsTier.new(monthly_price_in_cents: 2_00, yearly_price_in_cents: 24_00)
      patreon_tier = SponsorsPatreonTier.new(amount_in_cents: 1_00)
      refute sponsors_tier.equal_price?(patreon_tier)
    end
  end

  context "#equal_custom_tier?" do
    test "returns false if other_tier is nil" do
      refute @custom_tier.equal_custom_tier?(nil)
    end

    test "returns false if other_tier is not custom" do
      refute @custom_tier.equal_custom_tier?(@published_tier)
    end

    test "returns false if tier is not custom" do
      refute @published_tier.equal_custom_tier?(@custom_tier)
    end

    test "returns false if tiers differ in price" do
      other_tier = build(:sponsors_tier, :custom, listing: @custom_tier.listing,
        monthly_price_in_cents: @custom_tier.monthly_price_in_cents * 2)
      refute @custom_tier.equal_custom_tier?(other_tier)
    end

    test "returns false if tiers differ in frequency" do
      other_tier = build(:sponsors_tier, :custom, :one_time, listing: @custom_tier.listing,
        monthly_price_in_cents: 100_00, yearly_price_in_cents: 100_00 * 12)
      refute @custom_tier.equal_custom_tier?(other_tier)
    end

    test "returns false if tiers belongs to different listings" do
      other_tier = build(:sponsors_tier, :custom, :recurring,
        monthly_price_in_cents: @custom_tier.monthly_price_in_cents)
      refute @custom_tier.equal_custom_tier?(other_tier)
    end

    test "returns true if both tiers have same price, frequency, and listing" do
      other_tier = build(:sponsors_tier, :custom, :recurring, listing: @custom_tier.listing,
        monthly_price_in_cents: @custom_tier.monthly_price_in_cents)
      assert @custom_tier.equal_custom_tier?(other_tier)
    end
  end
end unless GitHub.enterprise?
