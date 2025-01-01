# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnGroupableOptionsTest < GitHub::TestCase
  fixtures do
    @field_id = create(:memex_project).memex_project_columns.find(&:title?).id
  end

  context "#initialize" do
    test "raises ArgumentError if grouped item page size settings exceed TOTAL_ITEM_LIMIT" do
      error = assert_raises ArgumentError do
        MemexProjectColumn::Groupable::Options.stub_const(:TOTAL_ITEM_LIMIT, 10) do
          MemexProjectColumn::Groupable::Options.new(
            field_object_or_id: @field_id,
            groups_page_size: 5,
            grouped_items_page_size: 8,
          )
        end
      end

      assert_equal "groups_page_size (5) * grouped_items_page_size (8) must be <= 10", error.message
    end

    test "raises ArgumentError if grouped item page size exceeds ES limits" do
      error = assert_raises ArgumentError do
        MemexProjectColumn::Groupable::Options.new(
          field_object_or_id: @field_id,

          # 2 * 100 is < MAX_PAGE_SIZE, but will exceed the ES limit: max_inner_result_window
          groups_page_size: 2,
          grouped_items_page_size: 100,
        )
      end

      assert_equal "grouped_items_page_size (100) must be <= 99", error.message
    end

    test "sets grouped items page size to optimal page size when less than max allowed" do
      max_items_page_size = 10
      MemexProjectColumn::Groupable::Options.stub_const(:MAX_GROUPED_ITEMS_PAGE_SIZE, max_items_page_size) do
        Search::Queries::MemexProjectItemQuery.stub_const(:MAX_PAGE_SIZE, 2) do
          options = MemexProjectColumn::Groupable::Options.new(
            field_object_or_id: @field_id,
            # A value of 1 here will yield 2 for optimal page size ( MAX_PAGE_SIZE / groups_page_size )
            groups_page_size: 1,
          )
          assert_equal 2, options.grouped_items_page_size
        end
      end
    end

    test "falls back to max grouped items page size when optimal page size is higher" do
      max_items_page_size = 1
      MemexProjectColumn::Groupable::Options.stub_const(:MAX_GROUPED_ITEMS_PAGE_SIZE, max_items_page_size) do
        Search::Queries::MemexProjectItemQuery.stub_const(:MAX_PAGE_SIZE, 2) do
          options = MemexProjectColumn::Groupable::Options.new(
            field_object_or_id: @field_id,
            # A value of 1 here will yield 2 for optimal page size ( MAX_PAGE_SIZE / groups_page_size )
            groups_page_size: 1,
          )
          assert_equal max_items_page_size, options.grouped_items_page_size
        end
      end
    end

    test "optimal page size falls back to 1 when groups_page_size is greater than max page size" do
      max_items_page_size = 10
      MemexProjectColumn::Groupable::Options.stub_const(:MAX_GROUPED_ITEMS_PAGE_SIZE, max_items_page_size) do
        Search::Queries::MemexProjectItemQuery.stub_const(:MAX_PAGE_SIZE, 2) do
          options = MemexProjectColumn::Groupable::Options.new(
            field_object_or_id: @field_id,
            # A value of 3 here will yield 0.66 for optimal page size ( MAX_PAGE_SIZE / groups_page_size )
            groups_page_size: 3,
          )
          assert_equal 1, options.grouped_items_page_size
        end
      end
    end

    test "raises ParameterError if grouped :after cursor is invalid" do
      error = assert_raises Platform::Errors::Cursor do
        MemexProjectColumn::Groupable::Options.new(
          field_object_or_id: @field_id,
          cursor: "nonsense"
        )
      end

      assert_equal "`nonsense` does not appear to be a valid cursor.", error.message
    end
  end
end
