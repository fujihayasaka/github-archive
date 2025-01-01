# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchFiltersEnterpriseFilterTest < GitHub::TestCase

  test "raises error if enterprise ids missing" do
    assert_raises(Search::Filters::EnterpriseFilter::EnterpriseFilterError) do
      Search::Filters::EnterpriseFilter.new
    end

    assert_raises(Search::Filters::EnterpriseFilter::EnterpriseFilterError) do
      Search::Filters::EnterpriseFilter.new(enterprise_ids: [])
    end
  end

  test "returns must clause for provided enterprise ids" do
    enterprise_ids = [1, 2, 3]
    filter = Search::Filters::EnterpriseFilter.new(enterprise_ids: enterprise_ids)
    expected_clause = { terms: { "_id" => enterprise_ids } }
    assert_equal expected_clause, filter.must
  end
end
