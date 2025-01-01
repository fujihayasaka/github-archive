# typed: true
# frozen_string_literal: true

require "test_helper"

module ApiInsights::Stats::Queries
  class PagerTest < GitHub::TestCase
    test "from rows" do
      pager = Pager.from_rows(1, 30)
      assert_equal 1, pager.min_row
      assert_equal 30, pager.max_row
    end

    test "from page" do
      pager = Pager.from_page(1, 30)
      assert_equal 1, pager.min_row
      assert_equal 30, pager.max_row

      pager = Pager.from_page(2, 30)
      assert_equal 31, pager.min_row
      assert_equal 60, pager.max_row
    end

    test "from rows invalid min row" do
      error = assert_raises(Error) { Pager.from_rows(0, 30) }
      assert_equal ErrorCode::PAGER_INVALID_MIN_ROW, error.code
    end

    test "from rows invalid max row" do
      error = assert_raises(Error) { Pager.from_rows(1, 0) }
      assert_equal ErrorCode::PAGER_INVALID_MAX_ROW, error.code
    end

    test "from rows min row after max row" do
      error = assert_raises(Error) { Pager.from_rows(31, 30) }
      assert_equal ErrorCode::PAGER_MIN_ROW_AFTER_MAX_ROW, error.code
    end

    test "from page invalid page" do
      error = assert_raises(Error) { Pager.from_page(0, 30) }
      assert_equal ErrorCode::PAGER_INVALID_PAGE, error.code
    end

    test "from page invalid page size" do
      error = assert_raises(Error) { Pager.from_page(1, 0) }
      assert_equal ErrorCode::PAGER_INVALID_PAGE_SIZE, error.code
    end

    test "to_s" do
      pager = Pager.from_rows(1, 30)
      expected_condition = "row_number() between (min_row_param..max_row_param)"
      assert_equal expected_condition, pager.to_s
    end

    test "to filter condition" do
      pager = Pager.from_rows(1, 30)
      expected_condition = "row_number() between (min_row_param..max_row_param)"
      assert_equal expected_condition, pager.to_filter_condition
    end

    test "parameters" do
      pager = Pager.from_rows(1, 30)
      expected_parameters = {
        "min_row_param" => 1,
        "max_row_param" => 30
      }
      assert_equal expected_parameters, pager.parameters
    end
  end
end
