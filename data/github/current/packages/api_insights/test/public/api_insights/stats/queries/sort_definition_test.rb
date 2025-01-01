# typed: true
# frozen_string_literal: true

require "test_helper"

module ApiInsights::Stats::Queries
  class SortDefinitionTest < GitHub::TestCase
    def setup
      @field = SortField::ActorId
    end

    test "initialize with defaults" do
      sort_definition = SortDefinition.new(@field)
      assert_equal @field, sort_definition.field
      assert_equal false, sort_definition.descending
    end

    test "initialize with parameters" do
      sort_definition = SortDefinition.new(@field, descending: true)
      assert_equal @field, sort_definition.field
      assert_equal true, sort_definition.descending
    end

    test "to_s ascending" do
      sort_definition = SortDefinition.new(@field)
      assert_equal "#{@field} asc", sort_definition.to_s
    end

    test "to_s descending" do
      sort_definition = SortDefinition.new(@field, descending: true)
      assert_equal "#{@field} desc", sort_definition.to_s
    end
  end
end
