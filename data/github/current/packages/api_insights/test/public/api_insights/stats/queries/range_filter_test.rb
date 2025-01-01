# typed: true
# frozen_string_literal: true

require "test_helper"

module ApiInsights::Stats::Queries
  class RangeFilterTest < GitHub::TestCase
    test "initialization" do
      filter = RangeFilter.new(FilterField::ActorId, 1, 2)
      assert_equal FilterField::ActorId, filter.field
      assert_equal 1, filter.value
      assert_equal 2, filter.max_value
    end

    test "condition" do
      filter = RangeFilter.new(FilterField::ActorId, 1, 2)
      assert_equal "actor_id >= min_actor_id_param and actor_id <= max_actor_id_param", filter.condition
    end

    test "parameters" do
      filter = RangeFilter.new(FilterField::ActorId, 1, 2)
      expected_params = {
        "min_actor_id_param" => 1,
        "max_actor_id_param" => 2
      }
      assert_equal expected_params, filter.parameters
    end
  end
end
