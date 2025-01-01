# typed: true
# frozen_string_literal: true

require "test_helper"

class MarketplaceUpdateMarketplaceListingPlanTest < GitHub::TestCase
  fixtures do
  end

  test "integration owner can update draft plan" do
    integration = create(:integration)
    listing = create(:marketplace_listing, listable: integration)
    plan = create(:marketplace_listing_plan, listing: listing)

    inputs = {
      plan: plan,
      name: "Fancy Pants Plan",
      description: "The most fancy pants",
      monthly_price_in_cents: 37_00,
      yearly_price_in_cents: 444_00,
      price_model: "per-unit",
      unit_name: "seat",
      for_account_type: "users_and_organizations",
      viewer: integration.owner.admin,
    }
    result = Marketplace::UpdateMarketplaceListingPlan.call(inputs)

    assert_equal inputs[:name], plan.reload.name
    assert_equal inputs[:description], plan.description
    assert_equal inputs[:monthly_price_in_cents], plan.monthly_price_in_cents
    assert_equal inputs[:price_model] == "per-unit", plan.per_unit?
    assert_equal inputs[:unit_name], plan.unit_name

    assert_equal inputs[:name], result[:marketplace_listing_plan].name
  end

  test "updates are instrumented" do
    events = subscribe "marketplace_listing_plan.update"

    listing = create(:marketplace_listing)
    plan = create(:marketplace_listing_plan, listing: listing)

    inputs = {
      plan: plan,
      name: "Fancy Pants Plan",
      description: "The most fancy pants",
      monthly_price_in_cents: 37_00,
      yearly_price_in_cents: 444_00,
      price_model: "per-unit",
      unit_name: "seat",
      for_account_type: "users_and_organizations",
      viewer: listing.owner,
    }
    Marketplace::UpdateMarketplaceListingPlan.call(inputs)

    assert event = events.pop, "an event was expected"
    assert_equal "marketplace_listing_plan.update", event.name
  end

  test "OAuth app owner can update draft plan" do
    app = create :oauth_application
    listing = create(:marketplace_listing, listable: app)
    plan = create(:marketplace_listing_plan, listing: listing)

    inputs = {
      plan: plan,
      name: "Truly Unique Plan",
      description: "This one is really special.",
      monthly_price_in_cents: 540_00,
      yearly_price_in_cents: 6480_00,
      price_model: "flat-rate",
      for_account_type: "users_and_organizations",
      viewer: app.user,
    }
    result = Marketplace::UpdateMarketplaceListingPlan.call(inputs)

    assert_equal inputs[:name], plan.reload.name
    assert_equal inputs[:description], plan.description
    assert_equal inputs[:monthly_price_in_cents], plan.monthly_price_in_cents
    assert_equal inputs[:price_model] == "per-unit", plan.per_unit?

    assert_equal inputs[:name], result[:marketplace_listing_plan].name
  end

  test "listing admin cannot update pricing on non-draft plan" do
    app = create :oauth_application
    listing = create(:marketplace_listing, :verified, listable: app)
    plan = create(:marketplace_listing_plan, :published, listing: listing)

    inputs = {
      plan: plan,
      name: plan.name,
      description: "This one is really special.",
      monthly_price_in_cents: 540_00,
      yearly_price_in_cents: plan.yearly_price_in_cents,
      price_model: "flat-rate",
      for_account_type: "users_and_organizations",
      viewer: app.user,
    }

    error = assert_raises Marketplace::UpdateMarketplaceListingPlan::UnprocessableError do
      Marketplace::UpdateMarketplaceListingPlan.call(inputs)
    end
    assert_equal "Could not update Marketplace listing plan: Monthly price in cents cannot be changed for a published plan", error.message
  end

  test "adding a free trial auto adds the listing to free-trial category" do
    listing = create(:marketplace_listing, :verified)
    plan = create(:marketplace_listing_plan, :published, listing: listing)
    free_trial_category = create(:marketplace_category, name: "Free trials", acts_as_filter: true)

    inputs = {
      plan: plan,
      name: plan.name,
      description: "This one is really special.",
      monthly_price_in_cents: plan.monthly_price_in_cents,
      yearly_price_in_cents: plan.yearly_price_in_cents,
      has_free_trial: true,
      price_model: "flat-rate",
      for_account_type: "users_and_organizations",
      viewer: listing.owner,
    }
    refute listing.categories.include?(free_trial_category)

    Marketplace::UpdateMarketplaceListingPlan.call(inputs)

    assert listing.categories.reload.include?(free_trial_category)
  end

  test "random user cannot update a draft plan" do
    listing = create(:marketplace_listing, :verified)
    plan = create(:marketplace_listing_plan, listing: listing)
    viewer = create(:user)

    inputs = {
      plan: plan,
      name: "Truly Unique Plan",
      description: "This one is really special.",
      monthly_price_in_cents: 540_00,
      yearly_price_in_cents: 6400_00,
      price_model: "flat-rate",
      for_account_type: "users_and_organizations",
      viewer: viewer,
    }

    error = assert_raises Marketplace::UpdateMarketplaceListingPlan::ForbiddenError do
      Marketplace::UpdateMarketplaceListingPlan.call(inputs)
    end
    assert_equal "#{viewer} does not have permission to change the Marketplace listing plan.", error.message
  end

  test "user not connected to the listing cannot update draft plan" do
    listing = create(:marketplace_listing)
    viewer = create(:user)
    plan = create(:marketplace_listing_plan, listing: listing)

    inputs = {
      plan: plan,
      name: "Bronze",
      description: "Bronzey goodness.",
      monthly_price_in_cents: 12_00,
      yearly_price_in_cents: 144_00,
      price_model: "per-unit",
      unit_name: "user",
      for_account_type: "users_and_organization",
      viewer: viewer,
    }

    error = assert_raises Marketplace::UpdateMarketplaceListingPlan::ForbiddenError do
      Marketplace::UpdateMarketplaceListingPlan.call(inputs)
    end
    assert_equal "#{viewer} does not have permission to change the Marketplace listing plan.", error.message
  end

  test "returns error when plan does not save" do
    viewer = create(:user)
    integration = create(:integration, owner: viewer)
    listing = create(:marketplace_listing, listable: integration)
    plan = create(:marketplace_listing_plan, listing: listing)

    inputs = {
      plan: plan,
      name: "", # cannot be blank, will cause save to fail
      description: "Decently speedy",
      monthly_price_in_cents: 25_00,
      yearly_price_in_cents: 290_00,
      price_model: "flat-rate",
      for_account_type: "users_and_organizations",
      viewer: viewer,
    }

    error = assert_raises Marketplace::UpdateMarketplaceListingPlan::UnprocessableError do
      Marketplace::UpdateMarketplaceListingPlan.call(inputs)
    end
    assert_equal "Could not update Marketplace listing plan: Name can't be blank, Name is too short (minimum is 1 character)", error.message
  end

  test "can update allowed subscriber types to users and organizations" do
    listing = create(:marketplace_listing)
    plan = create(:marketplace_listing_plan, listing: listing, subscription_rules: :for_users_only)

    assert_predicate plan, :for_users_only?

    inputs = {
      plan: plan,
      name: "Personal Account Plan",
      description: "Bronzey goodness.",
      monthly_price_in_cents: 12_00,
      yearly_price_in_cents: 144_00,
      price_model: "flat-rate",
      for_account_type: "users_and_organizations",
      viewer: listing.owner,
    }

    Marketplace::UpdateMarketplaceListingPlan.call(inputs)

    assert_nil plan.reload.subscription_rules
    refute_predicate plan, :for_users_only?
    refute_predicate plan, :for_organizations_only?
  end

  test "can update allowed subscriber types to users only" do
    listing = create(:marketplace_listing)
    plan = create(:marketplace_listing_plan, listing: listing)

    refute plan.for_users_only?

    inputs = {
      plan: plan,
      name: "Personal Account Plan",
      description: "Bronzey goodness.",
      monthly_price_in_cents: 12_00,
      yearly_price_in_cents: 144_00,
      price_model: "flat-rate",
      for_account_type: "users_only",
      viewer: listing.owner,
    }

    Marketplace::UpdateMarketplaceListingPlan.call(inputs)

    assert_predicate plan.reload, :for_users_only?
    refute_predicate plan, :for_organizations_only?
  end

  test "can update allowed subscriber types to organizations only" do
    listing = create(:marketplace_listing)
    plan = create(:marketplace_listing_plan, listing: listing)

    refute plan.for_organizations_only?

    inputs = {
      plan: plan,
      name: "Personal Account Plan",
      description: "Bronzey goodness.",
      monthly_price_in_cents: 12_00,
      yearly_price_in_cents: 144_00,
      price_model: "flat-rate",
      for_account_type: "organizations_only",
      viewer: listing.owner,
    }

    Marketplace::UpdateMarketplaceListingPlan.call(inputs)

    assert_predicate plan.reload, :for_organizations_only?
    refute_predicate plan, :for_users_only?
  end
end
