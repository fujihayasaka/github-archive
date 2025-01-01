# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessFeatureFlagMethodsTest < GitHub::TestCase
  context "#flipper_actor_names" do
    test "from_flipper_actor_name" do
      business = create :business
      # assert that getting the business from the flipper actor name returns the same business
      assert_equal business, Business.from_flipper_actor_name(business.flipper_actor_name)
      # assert that the flipper actor name has been overridden and is not the same as the flipper id
      refute_equal business.flipper_id, business.flipper_actor_name
      # assert that that flipper actor name is the slug
      assert_equal business.slug, business.flipper_actor_name
    end
  end
end
