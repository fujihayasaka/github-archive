# typed: true
# frozen_string_literal: true

require "test_helper"

class MarketplaceCreateMarketplaceListingPlanTest < GitHub::TestCase
  test "integration owner can create plan for their draft listing" do
    integration = create(:integration)
    listing = create(:marketplace_listing, listable: integration)

    inputs = {
      name: "Gold-tier Plan",
      slug: listing.slug,
      description: "Fast, reliable service",
      monthly_price_in_cents: 30_00,
      yearly_price_in_cents: 360_00,
      price_model: "per-unit",
      unit_name: "user",
      has_free_trial: true,
      for_account_type: "users_and_organizations",
      viewer: integration.owner.admin,
    }
    results = Marketplace::CreateMarketplaceListingPlan.call(inputs)

    assert plan = listing.listing_plans.last
    assert_equal inputs[:name], plan.name
    assert_equal inputs[:description], plan.description
    assert_equal inputs[:monthly_price_in_cents], plan.monthly_price_in_cents
    assert_equal inputs[:yearly_price_in_cents], plan.yearly_price_in_cents
    assert_equal inputs[:price_model] == "per-unit", plan.per_unit?
    assert_equal inputs[:unit_name], plan.unit_name
    assert_equal inputs[:has_free_trial], plan.has_free_trial?

    plan_result = results[:marketplace_listing_plan]
    assert_equal inputs[:name], plan_result[:name]
  end

  test "OAuth app owner can create plan for their draft listing" do
    app = create :oauth_application
    listing = create(:marketplace_listing, listable: app)

    inputs = {
      name: "Silver-tier Plan",
      slug: listing.slug,
      description: "Decently speedy",
      monthly_price_in_cents: 25_00,
      yearly_price_in_cents: 300_00,
      price_model: "flat-rate",
      has_free_trial: true,
      for_account_type: "users_and_organizations",
      viewer: app.user,
    }
    results = Marketplace::CreateMarketplaceListingPlan.call(inputs)

    assert plan = listing.listing_plans.last
    assert_equal inputs[:name], plan.name
    assert_equal inputs[:description], plan.description
    assert_equal inputs[:monthly_price_in_cents], plan.monthly_price_in_cents
    assert_equal inputs[:yearly_price_in_cents], plan.yearly_price_in_cents
    assert_equal inputs[:price_model] == "PER_UNIT", plan.per_unit?
    assert_equal inputs[:has_free_trial], plan.has_free_trial?

    plan_result = results[:marketplace_listing_plan]
    assert_equal inputs[:name], plan_result[:name]
  end

  test "user not connected to the listing cannot create listing plan for draft listing" do
    listing = create(:marketplace_listing)
    viewer = create(:user)

    inputs = {
      name: "Silver-tier Plan",
      slug: listing.slug,
      description: "Decently speedy",
      monthly_price_in_cents: 25_00,
      yearly_price_in_cents: 290_00,
      price_model: "flat-rate",
      has_free_trial: false,
      for_account_type: "users_and_organizations",
      viewer: viewer,
    }
    error = assert_raises Marketplace::CreateMarketplaceListingPlan::ForbiddenError do
      Marketplace::CreateMarketplaceListingPlan.call(inputs)
    end
    assert_equal "#{viewer.login} does not have permission to create a plan for the listing.", error.message
  end

  test "returns error when plan does not save" do
    viewer = create(:user)
    integration = create(:integration, owner: viewer)
    listing = create(:marketplace_listing, listable: integration)

    inputs = {
      name: "", # cannot be blank, will cause save to fail
      slug: listing.slug,
      description: "Decently speedy",
      monthly_price_in_cents: 25_00,
      yearly_price_in_cents: 290_00,
      price_model: "flat-rate",
      for_account_type: "users_and_organizations",
      viewer: viewer,
    }
    error = assert_raises Marketplace::CreateMarketplaceListingPlan::UnprocessableError do
      Marketplace::CreateMarketplaceListingPlan.call(inputs)
    end
    assert_includes error.message, "Could not create a Marketplace listing plan: Name can't be blank"
  end

  test "creates bullets with the plan" do
    integration = create(:integration)
    listing = create(:marketplace_listing, listable: integration)

    bullet_values = %w(Terrific Radiant Humble)
    inputs = {
      name: "Gold-tier Plan",
      slug: listing.slug,
      description: "Fast, reliable service",
      monthly_price_in_cents: 30_00,
      yearly_price_in_cents: 360_00,
      price_model: "per-unit",
      unit_name: "user",
      has_free_trial: true,
      bullet_values: bullet_values,
      for_account_type: "users_and_organizations",
      viewer: integration.owner.admin,
    }
    results = Marketplace::CreateMarketplaceListingPlan.call(inputs)

    assert plan = listing.listing_plans.last
    assert_same_elements bullet_values, plan.bullets.pluck(:value)
  end

  test "instruments creation of the plan" do
    events = subscribe "marketplace_listing_plan.create"
    listing = create(:marketplace_listing)

    inputs = {
      name: "Gold-tier Plan",
      slug: listing.slug,
      description: "Fast, reliable service",
      monthly_price_in_cents: 30_00,
      yearly_price_in_cents: 360_00,
      price_model: "per-unit",
      unit_name: "user",
      has_free_trial: true,
      for_account_type: "users_and_organizations",
      viewer: listing.owner,
    }
    results = Marketplace::CreateMarketplaceListingPlan.call(inputs)

    assert event = events.pop, "an event was expected"
    assert_equal "marketplace_listing_plan.create", event.name
  end

  test "can set allowed subscriber types to users and organizations during creation" do
    listing = create(:marketplace_listing)

    inputs = {
      name: "Gold-tier Plan",
      slug: listing.slug,
      description: "Fast, reliable service",
      monthly_price_in_cents: 30_00,
      yearly_price_in_cents: 360_00,
      price_model: "per-unit",
      unit_name: "user",
      has_free_trial: true,
      for_account_type: "users_and_organizations",
      viewer: listing.owner,
    }
    results = Marketplace::CreateMarketplaceListingPlan.call(inputs)

    assert plan = listing.listing_plans.last
    refute_predicate plan, :for_users_only?
    refute_predicate plan, :for_organizations_only?
  end

  test "can set allowed subscriber types to users only during creation" do
    listing = create(:marketplace_listing)

    inputs = {
      name: "Gold-tier Plan",
      slug: listing.slug,
      description: "Fast, reliable service",
      monthly_price_in_cents: 30_00,
      yearly_price_in_cents: 360_00,
      price_model: "per-unit",
      unit_name: "user",
      has_free_trial: true,
      for_account_type: "users_only",
      viewer: listing.owner,
    }
    results = Marketplace::CreateMarketplaceListingPlan.call(inputs)

    assert plan = listing.listing_plans.last
    assert_predicate plan, :for_users_only?
    refute_predicate plan, :for_organizations_only?
  end

  test "can set allowed subscriber types to organizations only during creation" do
    listing = create(:marketplace_listing)

    inputs = {
      name: "My Org Only Plan Plan",
      slug: listing.slug,
      description: "Fast, reliable service",
      monthly_price_in_cents: 30_00,
      yearly_price_in_cents: 360_00,
      price_model: "per-unit",
      unit_name: "user",
      has_free_trial: true,
      for_account_type: "organizations_only",
      viewer: listing.owner,
    }
    results = Marketplace::CreateMarketplaceListingPlan.call(inputs)

    assert plan = listing.listing_plans.last
    assert_predicate plan, :for_organizations_only?
    refute_predicate plan, :for_users_only?
  end
end
