# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class Api::Serializer::SponsorsTierDependencyTest < Api::SerializerTestCase
  setup do
    @created_at = Time.now
    travel_to(@created_at) do
      @tier = create(:sponsors_tier, :published, monthly_price_in_cents: 5_00,
        description: "My favorite tier")
      @one_time_tier = create(:sponsors_tier, :published, :one_time, monthly_price_in_cents: 10_00,
        description: "A wee bit of money")
      @custom_tier = create(:sponsors_tier, :custom, monthly_price_in_cents: 12_00,
        description: "I chose this amount personally")
      @custom_one_time_tier = create(:sponsors_tier, :custom, :one_time,
        monthly_price_in_cents: 80_00, description: "test test")
    end
  end

  def assert_equal_json(expected, tier)
    serialized_hash = Api::Serializer.serialize(:sponsors_tier_hash, tier)

    # Run it through JSON parser so we get an idea of what it will look like when
    # being returned by the API:
    json = JSON.parse(serialized_hash.to_json)

    assert_equal expected, json
  end

  context "#sponsors_tier_hash" do
    test "serializes a recurring, non-custom Sponsors tier" do
      expected = {
        "node_id" => @tier.global_relay_id,
        "created_at" => @created_at.to_time.utc.xmlschema,
        "description" => "My favorite tier",
        "monthly_price_in_cents" => 5_00, # https://github.com/github/docs/issues/3493
        "monthly_price_in_dollars" => 5,  # https://github.com/github/docs/issues/3493
        "name" => "$5 a month",
        "is_one_time" => false,
        "is_custom_amount" => false,
      }

      assert_equal_json expected, @tier
    end

    test "serializes a one-time, non-custom Sponsors tier" do
      expected = {
        "node_id" => @one_time_tier.global_relay_id,
        "created_at" => @created_at.to_time.utc.xmlschema,
        "description" => "A wee bit of money",
        "monthly_price_in_cents" => 10_00,
        "monthly_price_in_dollars" => 10,
        "name" => "$10 one time",
        "is_one_time" => true,
        "is_custom_amount" => false,
      }

      assert_equal_json expected, @one_time_tier
    end

    test "serializes a recurring, custom Sponsors tier" do
      expected = {
        "node_id" => @custom_tier.global_relay_id,
        "created_at" => @created_at.to_time.utc.xmlschema,
        "description" => "I chose this amount personally",
        "monthly_price_in_cents" => 12_00,
        "monthly_price_in_dollars" => 12,
        "name" => "$12 a month",
        "is_one_time" => false,
        "is_custom_amount" => true,
      }

      assert_equal_json expected, @custom_tier
    end

    test "serializes a one-time, custom Sponsors tier" do
      expected = {
        "node_id" => @custom_one_time_tier.global_relay_id,
        "created_at" => @created_at.to_time.utc.xmlschema,
        "description" => "test test",
        "monthly_price_in_cents" => 80_00,
        "monthly_price_in_dollars" => 80,
        "name" => "$80 one time",
        "is_one_time" => true,
        "is_custom_amount" => true,
      }

      assert_equal_json expected, @custom_one_time_tier
    end

    test "returns nil when no tier is given" do
      assert_nil Api::Serializer.serialize(:sponsors_tier_hash, nil)
    end
  end
end
