# typed: true
# frozen_string_literal: true

require "test_helper"

class Search::Repositories::EsSearchTest < GitHub::TestCase
  include Search::Repositories

  setup do
    setup_search

    @org = create :organization
    @public_repos = create_list :repository, 3, owner: @org
    make_searchable(*@public_repos)
  end

  teardown do
    teardown_search
  end

  test "search repos in the org" do
    results = EsSearch.search(@org, @org.admins.first, "visibility:public", 1, per_page: 10, sort_order: nil, user_session: nil, cap_filter: nil, limit_to_repo_ids: nil)
    assert_equal 3, results[:repos].size
  end
end
