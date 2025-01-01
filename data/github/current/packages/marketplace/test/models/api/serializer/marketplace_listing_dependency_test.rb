# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class MarketplaceListingSerializersTest < Api::SerializerTestCase
  SubscriptionItemQuery = Api::App::PlatformClient.parse(<<-'GRAPHQL')
    query($id: ID!, $planBulletsLimit: Int!) {
      node(id: $id) {
        ...Api::Serializer::MarketplaceListingDependency::SubscriptionItemFragment
      }
    }
  GRAPHQL

  context "#graphql_marketplace_listing_plan_hash" do
    test "includes plan details" do
      plan = {}

      Api::Serializer::MarketplaceListingDependency::MarketplaceListingPlanFragment.stub(:new, plan_fragment) do
        @result = Api::Serializer.serialize(:graphql_marketplace_listing_plan_hash, plan)
      end

      assert_equal plan_fragment.database_id, @result[:id]
      assert_equal plan_fragment.name, @result[:name]
      assert_equal plan_fragment.description, @result[:description]
      assert_equal plan_fragment.monthly_price_in_cents, @result[:monthly_price_in_cents]
      assert_equal plan_fragment.yearly_price_in_cents, @result[:yearly_price_in_cents]
      assert_equal plan_fragment.price_model, @result[:price_model]
      assert_equal plan_fragment.unit_name, @result[:unit_name]
      assert_equal plan_fragment.has_free_trial, @result[:has_free_trial]
    end

    test "includes bullets" do
      first_bullet_value = "First bullet"
      second_bullet_value = "Second bullet"
      first_bullet_edge = OpenStruct.new(node: OpenStruct.new(value: first_bullet_value))
      second_bullet_edge = OpenStruct.new(node: OpenStruct.new(value: second_bullet_value))
      bullets = OpenStruct.new(edges: [first_bullet_edge, second_bullet_edge])
      plan_fragment_with_bullets = plan_fragment(bullets: bullets)
      plan = {}

      Api::Serializer::MarketplaceListingDependency::MarketplaceListingPlanFragment.stub(:new, plan_fragment_with_bullets) do
        @result = Api::Serializer.serialize(:graphql_marketplace_listing_plan_hash, plan)
      end

      assert_equal @result[:bullets], [first_bullet_value, second_bullet_value]
    end
  end

  context "#graphql_subscription_item_hash" do
    test "payload is valid" do
      subscription_item = create(:billing_subscription_item)
      subscription_item.account.update!(plan_duration: "month")
      results = Api::App::PlatformClient.query(SubscriptionItemQuery, variables: { "id": subscription_item.global_relay_id, "planBulletsLimit": 1 }, context: { viewer: subscription_item.account })
      output = Api::Serializer.serialize(:graphql_subscription_item_hash, results.data.node).with_indifferent_access
      assert output.key?("url")
      assert output.key?("type")
      assert output.key?("id")
      assert output.key?("login")
    end
  end

  context "#graphql_marketplace_purchase_hash" do
    test "payload is valid" do
      subscription_item = create(:billing_subscription_item)
      subscription_item.account.update!(plan_duration: "month")
      results = Api::App::PlatformClient.query(SubscriptionItemQuery, variables: { "id": subscription_item.global_relay_id, "planBulletsLimit": 1 }, context: { viewer: subscription_item.account })
      output = Api::Serializer.serialize(:graphql_marketplace_purchase_hash, results.data.node).with_indifferent_access
      assert output.key?("account")
      assert output.key?("billing_cycle")
      assert output.key?("unit_count")
      assert output.key?("next_billing_date")
    end
  end

  def plan_fragment(bullets: empty_bullets)
    OpenStruct.new(
      database_id: 1,
      name: "Free",
      number: 2,
      description: "Plan description",
      monthly_price_in_cents: 0,
      yearly_price_in_cents: 0,
      has_free_trial: false,
      price_model: Marketplace::ListingPlan::FLAT_RATE_PRICE_MODEL,
      unit_name: "seat",
      state: "published",
      bullets: bullets,
    )
  end

  def empty_bullets
    OpenStruct.new(edges: [])
  end
end
