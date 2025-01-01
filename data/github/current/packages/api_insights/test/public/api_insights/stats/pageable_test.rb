# typed: true
# frozen_string_literal: true

require "test_helper"

module ApiInsights::Stats
  class PageableTest < GitHub::TestCase
    setup do
      @pageable = FakePageable.new
    end

    test "adds paging" do
      @pageable.with_paging(page: 1, per_page: 10)
      refute_nil @pageable.query.pager
      assert_equal 1, @pageable.query.pager.min_row
      assert_equal 10, @pageable.query.pager.max_row
    end

    test "fails when passed invalid page" do
      error = assert_raises(Error) { @pageable.with_paging(page: 0, per_page: 10) }
      assert_equal ErrorCode::PAGER_INVALID_PAGE, error.code
    end

    test "fails when passed invalid per_page" do
      error = assert_raises(Error) { @pageable.with_paging(page: 1, per_page: 0) }
      assert_equal ErrorCode::PAGER_INVALID_PAGE_SIZE, error.code

      error = assert_raises(Error) { @pageable.with_paging(page: 1, per_page: Queries::Pager::MAX_PER_PAGE + 1) }
      assert_equal ErrorCode::PAGER_INVALID_PAGE_SIZE, error.code
    end
  end

  class FakePageable < StatsBase
    include Pageable

    def initialize
      now = Time.now.utc
      super 1, now - 1.day, now
    end

    def query
      super
    end
  end
end
