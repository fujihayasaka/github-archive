# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsCreateSponsorsTierTest < GitHub::TestCase
  setup do
    @inputs = {
      description: "A notebook for my thoughts",
      amount: 5, # $5.00 USD
      custom: false,
      is_recurring: true,
      welcome_message: "Welcome new sponsor!",
    }
    @custom_amount = 123
  end

  fixtures do
    @approved_listing = create(:sponsors_listing, :approved)
    @approved_listing_with_custom_tiers = create(:sponsors_listing, :approved)
    @sponsor = create(:user)
  end

  context ".find_published_or_create_custom_tier" do
    test "returns published tier of the same price and frequency when it exists for that listing" do
      listing = @approved_listing_with_custom_tiers
      published_tier = listing.default_tier

      result = assert_no_difference(-> { SponsorsTier.count }) do
        Sponsors::CreateSponsorsTier.find_published_or_create_custom_tier(
          sponsors_listing: listing,
          amount: published_tier.monthly_price_in_dollars.to_i,
          is_recurring: published_tier.recurring?,
        )
      end

      assert_equal published_tier, result
    end

    test "creates a new custom tier when no matching published tier exists for that listing" do
      listing = @approved_listing_with_custom_tiers
      published_tier = listing.default_tier
      dollar_amount = published_tier.monthly_price_in_dollars.to_i + 1
      viewer = create(:user, :verified)

      result = assert_difference(-> { SponsorsTier.count }) do
        Sponsors::CreateSponsorsTier.find_published_or_create_custom_tier(
          sponsors_listing: listing,
          amount: dollar_amount,
          is_recurring: true,
          viewer: viewer,
          sponsor: viewer,
        )
      end

      refute_equal published_tier, result
      assert_instance_of SponsorsTier, result
      assert_predicate result, :custom?
      assert_equal dollar_amount * 100, result.monthly_price_in_cents
      assert_predicate result, :recurring?
      assert_equal listing, result.sponsors_listing
      assert_equal viewer, result.creator
      assert_nil result.parent_tier, "should not have set parent tier when no ID was given"
    end

    test "sets parent_tier_id on new custom tier when it's given" do
      listing = @approved_listing_with_custom_tiers
      published_tier = listing.default_tier
      dollar_amount = published_tier.monthly_price_in_dollars.to_i + 1
      viewer = create(:user, :verified)

      result = assert_difference(-> { SponsorsTier.count }) do
        Sponsors::CreateSponsorsTier.find_published_or_create_custom_tier(
          sponsors_listing: listing,
          amount: dollar_amount,
          is_recurring: published_tier.recurring?,
          viewer: viewer,
          sponsor: viewer,
          parent_tier_id: published_tier.id,
        )
      end

      refute_equal published_tier, result
      assert_instance_of SponsorsTier, result
      assert_predicate result, :custom?
      assert_equal dollar_amount * 100, result.monthly_price_in_cents
      assert_equal published_tier.recurring?, result.recurring?
      assert_equal listing, result.sponsors_listing
      assert_equal viewer, result.creator
      assert_equal published_tier, result.parent_tier
    end
  end

  context "sponsors tiers creation" do
    test "sponsorable can create tiers for their draft Sponsors listing" do
      sponsors_listing = create(:sponsors_listing)

      results = Sponsors::CreateSponsorsTier.call(@inputs.merge(
        sponsors_listing: sponsors_listing,
        viewer: sponsors_listing.sponsorable,
      ))

      assert tier = sponsors_listing.sponsors_tiers.last
      assert_equal "$5 a month", tier.name
      assert_predicate tier, :draft?
      assert_equal sponsors_listing.sponsorable, tier.creator
      assert_equal @inputs[:description], tier.description
      assert_equal @inputs[:welcome_message], tier.welcome_message
      assert_equal @inputs[:amount], tier.monthly_price_in_dollars.to_i
      assert_equal @inputs[:amount] * 12 * 100, tier.yearly_price_in_cents
      assert_predicate tier, :recurring?
    end

    test "sets the repository on new tier" do
      listing = create(:sponsors_listing, :for_org, :approved)
      org = listing.sponsorable
      repo = create(:private_repository, owner: org)
      amount = listing.default_tier.monthly_price_in_dollars.to_i + 100

      result = assert_difference(-> { listing.sponsors_tiers.count }) do
        Sponsors::CreateSponsorsTier.call(@inputs.merge(
          sponsors_listing: listing,
          viewer: org.admin,
          repository_id: repo.id,
          amount: amount,
        ))
      end

      tier = listing.sponsors_tiers.last
      assert_equal repo, tier.repository
      assert_equal @inputs[:description], tier.description
      assert_equal @inputs[:welcome_message], tier.welcome_message
      assert_equal amount, tier.monthly_price_in_dollars.to_i
      assert_equal amount * 12 * 100, tier.yearly_price_in_cents
      assert_predicate tier, :recurring?
      assert_predicate tier, :draft?
      assert_equal org.admin, tier.creator
    end

    test "bypasses the maximum amount validation for Sponsors-invoiced sponsors" do
      sponsors_listing = @approved_listing_with_custom_tiers
      sponsor = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
      amount = SponsorsTier::MAX_SPONSORSHIP_AMOUNT_IN_DOLLARS + 1

      results = Sponsors::CreateSponsorsTier.call(@inputs.merge(
        sponsors_listing: sponsors_listing,
        viewer: sponsor,
        sponsor: sponsor,
        custom: true,
        amount: amount,
      ))

      assert tier = sponsors_listing.sponsors_tiers.last
      formatted_amount = Billing::Money.new(amount * 100).format(no_cents_if_whole: true)
      assert_equal "#{formatted_amount} a month", tier.name
      assert_predicate tier, :custom?
      assert_equal sponsor, tier.creator
      assert_predicate tier, :recurring?
      assert_equal @inputs[:description], tier.description
      assert_equal @inputs[:welcome_message], tier.welcome_message
      assert_equal amount * 100, tier.monthly_price_in_cents
      assert_equal amount * 100 * 12, tier.yearly_price_in_cents
    end

    test "sponsorable can create one-time tiers for their draft Sponsors listing" do
      sponsors_listing = create(:sponsors_listing)

      results = Sponsors::CreateSponsorsTier.call(@inputs.merge(
        sponsors_listing: sponsors_listing,
        viewer: sponsors_listing.sponsorable,
        is_recurring: false,
      ))

      tier = sponsors_listing.sponsors_tiers.where(name: "$5 one time").first
      refute_nil tier, "should have created a new tier with 'one time' in the name"
      assert_equal "$5 one time", tier.name
      assert_equal @inputs[:description], tier.description
      assert_equal @inputs[:welcome_message], tier.welcome_message
      assert_equal @inputs[:amount], tier.monthly_price_in_dollars.to_i
      assert_equal @inputs[:amount] * 100, tier.yearly_price_in_cents
      assert_predicate tier, :one_time?
    end

    test "sponsor can create custom tiers for an approved Sponsors listing" do
      sponsors_listing = @approved_listing_with_custom_tiers
      sponsor = @sponsor

      results = Sponsors::CreateSponsorsTier.call(@inputs.merge(
        sponsors_listing: sponsors_listing,
        viewer: sponsor,
        sponsor: sponsor,
        custom: true,
        amount: @custom_amount,
      ))

      assert tier = sponsors_listing.sponsors_tiers.last
      assert_equal "$#{@custom_amount} a month", tier.name
      assert_predicate tier, :custom?
      assert_equal sponsor, tier.creator
      assert_predicate tier, :recurring?
      assert_equal @inputs[:description], tier.description
      assert_equal @inputs[:welcome_message], tier.welcome_message
      assert_equal @custom_amount * 100, tier.monthly_price_in_cents
      assert_equal @custom_amount * 100 * 12, tier.yearly_price_in_cents
    end

    test "raises an error when creating a custom tier below the listing's minimum custom amount" do
      sponsors_listing = @approved_listing_with_custom_tiers
      min_amount = @custom_amount + 1
      sponsors_listing.min_custom_tier_amount_in_dollars = min_amount
      sponsors_listing.save!
      sponsor = @sponsor

      assert @custom_amount < sponsors_listing.min_custom_tier_amount_in_dollars, "amount should be below minimum"

      error = assert_raises Sponsors::CreateSponsorsTier::UnprocessableError do
        Sponsors::CreateSponsorsTier.call(@inputs.merge(
          sponsors_listing: sponsors_listing,
          viewer: sponsors_listing.sponsorable,
          sponsor: sponsor,
          custom: true,
          amount: @custom_amount,
        ))
      end
      assert_equal "Could not create new Sponsors tier: Monthly price must be at least $#{min_amount}", error.message
    end

    test "invoiced sponsor can create custom tiers" do
      sponsors_listing = @approved_listing
      invoiced_sponsor = create(:invoiced_organization, :sponsors_invoiced)

      results = Sponsors::CreateSponsorsTier.call(@inputs.merge(
        sponsors_listing: sponsors_listing,
        viewer: invoiced_sponsor.admin,
        sponsor: invoiced_sponsor,
        custom: true,
        amount: @custom_amount,
      ))

      assert tier = sponsors_listing.sponsors_tiers.last
      assert_equal "$#{@custom_amount} a month", tier.name
      assert_predicate tier, :custom?
      assert_equal invoiced_sponsor.admin, tier.creator
      assert_predicate tier, :recurring?
      assert_equal @inputs[:description], tier.description
      assert_equal @inputs[:welcome_message], tier.welcome_message
      assert_equal @custom_amount * 100, tier.monthly_price_in_cents
      assert_equal @custom_amount * 100 * 12, tier.yearly_price_in_cents
    end

    test "raises an error when non-sponsorable attempts to create draft tier" do
      user = create(:user)
      sponsors_listing = create(:sponsors_listing)

      error = assert_raises Sponsors::CreateSponsorsTier::ForbiddenError do
        Sponsors::CreateSponsorsTier.call(@inputs.merge(
          sponsors_listing: sponsors_listing,
          viewer: user,
          custom: false,
        ))
      end
      assert_equal "#{user.login} does not have permission to create a Sponsors tier " \
        "for #{sponsors_listing.sponsorable_login}.", error.message
    end

    test "raises an error when tier does not save" do
      sponsors_listing = create(:sponsors_listing)

      error = assert_raises Sponsors::CreateSponsorsTier::UnprocessableError do
        Sponsors::CreateSponsorsTier.call(@inputs.merge(
          sponsors_listing: sponsors_listing,
          viewer: sponsors_listing.sponsorable,
          amount: 0,
        ))
      end
      assert_equal "Could not create new Sponsors tier: Monthly price must be " \
        "greater than 0, Annual price must be greater than 0", error.message
    end
  end
end unless GitHub.enterprise?
