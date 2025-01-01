# typed: true
# frozen_string_literal: true

require "test_helper"

module ApiInsights::Stats
  class SortableTest < GitHub::TestCase
    setup do
      @sortable = FakeSortable.new
    end

    test "adds sorting" do
      assert_empty @sortable.query.sort_definitions

      @sortable.with_sorting([
        Queries::SortDefinition.new(Queries::SortField::SubjectName, descending: false),
        Queries::SortDefinition.new(Queries::SortField::ApiRoute, descending: true)
      ])

      assert_equal 2, @sortable.query.sort_definitions.size
      assert @sortable.query.sort_definitions.any? { |d| d.field == Queries::SortField::SubjectName && d.descending == false }
      assert @sortable.query.sort_definitions.any? { |d| d.field == Queries::SortField::ApiRoute && d.descending == true }
    end
  end

  class FakeSortable < StatsBase
    include Sortable

    def initialize
      now = Time.now.utc
      super 1, now - 1.day, now
    end

    def query
      super
    end
  end
end
