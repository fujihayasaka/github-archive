# typed: true
# frozen_string_literal: true

require "test_helper"

module ApiInsights::Stats::Queries
  class FilterTest < GitHub::TestCase
    test "condition" do
      filter = Filter.new(FilterField::ActorId, "bar")
      assert_equal "actor_id == actor_id_param", filter.condition
    end

    test "overriden condition" do
      filter = Filter.new(FilterField::ActorId, "bar", operator: "<")
      assert_equal "actor_id < actor_id_param", filter.condition
    end

    test "startswith condition" do
      filter = Filter.new(FilterField::ActorName, "bar", operator: "startswith")
      assert_equal "actor_name startswith actor_name_param", filter.condition
    end
  end
end
