# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchFiltersProjectOwnerFilterTest < GitHub::TestCase
  test "owner_id must be specified" do
    assert_raises(ArgumentError) { Search::Filters::ProjectOwnerFilter.new({}) }
  end

  test "owner_type must be specified" do
    assert_raises(ArgumentError) { Search::Filters::ProjectOwnerFilter.new({ owner_id: 5 }) }
  end

  test "owner_type must be 'org' or 'user'" do
    assert_raises(ArgumentError) { Search::Filters::ProjectOwnerFilter.new({ owner_id: 5, owner_type: "repository" }) }
  end

  test "generates a term filter for org owner" do
    filter = Search::Filters::ProjectOwnerFilter.new({ owner_id: 5, owner_type: "org" })
    assert_equal({ term: { org_id: 5 } }, filter.must)
  end

  test "generates a term filter for a user owner" do
    filter = Search::Filters::ProjectOwnerFilter.new({ owner_id: 3, owner_type: "user" })
    assert_equal({ term: { user_id: 3 } }, filter.must)
  end
end
