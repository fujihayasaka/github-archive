# typed: true
# frozen_string_literal: true

require "test_helper"

module ApiInsights::Stats::Queries
  class BaseFilterTest < GitHub::TestCase
    class FakeFilter < BaseFilter
      def condition
        "some condition"
      end
    end

    test "initialize" do
      filter = FakeFilter.new(FilterField::ActorId, "bar")
      assert_equal FilterField::ActorId, filter.field
      assert_equal "bar", filter.value
      assert_equal "actor_id_param", filter.parameter_name
    end
  end
end
