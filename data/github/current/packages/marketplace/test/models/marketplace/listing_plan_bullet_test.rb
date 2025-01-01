# typed: true
# frozen_string_literal: true

require "test_helper"

class MarketplaceListingPlanBulletTest < GitHub::TestCase
  context "validations" do
    test "requires a plan" do
      bullet = Marketplace::ListingPlanBullet.new(listing_plan: nil)

      refute_predicate bullet, :valid?
      assert_predicate bullet.errors[:listing_plan], :any?
    end

    test "requires a value" do
      bullet = Marketplace::ListingPlanBullet.new(value: nil)

      refute_predicate bullet, :valid?
      assert_predicate bullet.errors[:value], :any?
    end

    test "rejects a value containing emoji" do
      bullet = Marketplace::ListingPlanBullet.new(value: "🐹")

      refute_predicate bullet, :valid?
      assert_predicate bullet.errors[:value], :any?
    end

    test "requires a unique value per plan" do
      existing = create :marketplace_listing_plan_bullet
      bullet = Marketplace::ListingPlanBullet.new(value: existing.value,
                                                  listing_plan: existing.listing_plan)
      refute_predicate bullet, :valid?
      assert_predicate bullet.errors[:value], :any?

      bullet.value = existing.value.upcase
      refute_predicate bullet, :valid?
      assert_predicate bullet.errors[:value], :any?
    end

    test "disallows more than 4 bullets per plan" do
      plan = create(:marketplace_listing_plan)
      4.times { |_i| create(:marketplace_listing_plan_bullet, listing_plan: plan) }

      bullet = build(:marketplace_listing_plan_bullet, listing_plan: plan)

      refute_predicate bullet, :valid?
      assert_predicate bullet.errors[:listing_plan], :any?
    end

    test "allows editing one of the four allowed bullets" do
      plan = create(:marketplace_listing_plan)
      4.times { |_i| create(:marketplace_listing_plan_bullet, listing_plan: plan) }

      bullet = plan.bullets.last
      bullet.value = "Some brand new thing"

      assert_predicate bullet, :valid?
      assert bullet.save
    end
  end

  context "#allowed_to_edit?" do
    test "true when user is integration owner admin" do
      integration = create(:integration)
      listing = create(:marketplace_listing, listable: integration)
      plan = create(:marketplace_listing_plan, listing: listing)
      bullet = Marketplace::ListingPlanBullet.new(listing_plan: plan)

      assert bullet.allowed_to_edit?(integration.owner.admin)
    end

    test "true when user is OAuth app user" do
      app = create :oauth_application
      listing = create(:marketplace_listing, listable: app)
      plan = create(:marketplace_listing_plan, listing: listing)
      bullet = Marketplace::ListingPlanBullet.new(listing_plan: plan)

      assert bullet.allowed_to_edit?(app.user)
    end

    test "false when user is unrelated to integration owner" do
      integration = create(:integration)
      listing = create(:marketplace_listing, listable: integration)
      plan = create(:marketplace_listing_plan, listing: listing)
      bullet = Marketplace::ListingPlanBullet.new(listing_plan: plan)

      refute bullet.allowed_to_edit?(create(:user))
    end

    test "false when user is a regular member of integration owner" do
      integration = create(:integration)
      member = create(:user)
      integration.owner.add_member(member)

      listing = create(:marketplace_listing, listable: integration)
      plan = create(:marketplace_listing_plan, listing: listing)
      bullet = Marketplace::ListingPlanBullet.new(listing_plan: plan)

      refute bullet.allowed_to_edit?(member)
    end

    test "false when user is not OAuth app user" do
      app = create :oauth_application
      listing = create(:marketplace_listing, listable: app)
      plan = create(:marketplace_listing_plan, listing: listing)
      bullet = Marketplace::ListingPlanBullet.new(listing_plan: plan)

      refute bullet.allowed_to_edit?(create(:user))
    end

    test "true when the listing is approved" do
      app = create :oauth_application
      listing = create(:marketplace_listing, :verified, listable: app)
      plan = create(:marketplace_listing_plan, :published, listing: listing)
      bullet = Marketplace::ListingPlanBullet.new(listing_plan: plan)

      assert bullet.allowed_to_edit?(app.user)
    end

    test "false when the plan is retired" do
      app = create :oauth_application
      listing = create(:marketplace_listing, :verified, listable: app)
      plan = create(:marketplace_listing_plan, :retired, listing: listing)
      bullet = Marketplace::ListingPlanBullet.new(listing_plan: plan)

      refute bullet.allowed_to_edit?(app.user)
    end
  end
end
