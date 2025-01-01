# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesCursorPaginatedRepoQueryTest < GitHub::TestCase
  fixtures do
    @admin = create(:user)
    @org = create(:organization, admin: @admin)

    @repos = []
    freeze_time do
      5.times do |i|
        @repos << create(:repository, owner: @org, pushed_at: Time.current - i.days, stargazer_count: rand(1..20))
        @repos << create(:private_repository, owner: @org, pushed_at: Time.current - i.days, stargazer_count: rand(1..20))
      end
    end
  end

  setup do
    setup_search
  end

  teardown do
    teardown_search
  end

  test "find text in multiple fields" do
    in_title_repo = create :repository, name: "one-two"
    in_description_repo = create :repository, name: "descr", description: "a mix of one and two words"
    mixed_repo = create :repository, name: "one", description: "two cars"
    make_searchable(in_title_repo, in_description_repo, mixed_repo)

    query = Search::Queries::CursorPaginatedRepoQuery.new(current_user: create(:user), query: "one two")
    results = query.execute

    assert_same_elements %w(one-two descr one), results.results.map { |item| item.dig("_source", "name") }
  end

  context "pagination" do
    test "paginate results when there is no sort parameter passed into the query (sort by stars desc by default, break ties by repo_id asc)" do
      make_searchable(*@repos)
      expected_repo_ids = Repository.where(owner_id: @org.id).order(watcher_count: :desc, id: :asc).pluck(:id)

      # Fetch the first page
      query = Search::Queries::CursorPaginatedRepoQuery.new(current_user: @admin, phrase: "", per_page: 5)
      first_page = query_org_repos(query)

      assert_equal expected_repo_ids[0..4], first_page.results.map { |item| item["_id"].to_i }
      assert first_page.has_next_page, "Expected first page to have a next page"
      refute first_page.has_previous_page, "Expected first page to not have a previous page"

      # Fetch the second page
      query = Search::Queries::CursorPaginatedRepoQuery.new(current_user: @admin, phrase: "", per_page: 5, after: first_page.end_cursor)
      second_page = query_org_repos(query)

      assert_equal expected_repo_ids[5..9], second_page.results.map { |item| item["_id"].to_i }
      refute second_page.has_next_page, "Expected second page to not have a next page"
      assert second_page.has_previous_page, "Expected second page to have a previous page"

      # Fetch the page before the second page (first page)
      # We are providing the `last` instead of `per_page` arg in order to get the previous page (last X results that come before the cursor)
      query = Search::Queries::CursorPaginatedRepoQuery.new(current_user: @admin, phrase: "", last: 5, before: second_page.start_cursor)
      previous_page = query_org_repos(query)

      assert_equal expected_repo_ids[0..4], previous_page.results.map { |item| item["_id"].to_i }
      assert previous_page.has_next_page, "Expected previous page to have a next page"
      refute previous_page.has_previous_page, "Expected previous page to not have a previous page"
    end

    test "paginates results based on sort parameter passed into the query (updated desc)" do
      make_searchable(*@repos)
      expected_repo_ids = Repository.where(owner_id: @org.id).order(pushed_at: :desc, id: :asc).pluck(:id)

      # Fetch the first page
      query = Search::Queries::CursorPaginatedRepoQuery.new(current_user: @admin, phrase: "sort:updated", per_page: 4)
      first_page = query_org_repos(query)

      assert_equal expected_repo_ids[0..3], first_page.results.map { |item| item["_id"].to_i }
      assert first_page.has_next_page, "Expected first page to have a next page"
      refute first_page.has_previous_page, "Expected first page to not have a previous page"

      # Fetch the second page
      query = Search::Queries::CursorPaginatedRepoQuery.new(current_user: @admin, phrase: "sort:updated", per_page: 4, after: first_page.end_cursor)
      second_page = query_org_repos(query)

      assert_equal expected_repo_ids[4..7], second_page.results.map { |item| item["_id"].to_i }
      assert second_page.has_next_page, "Expected second page to have a next page"
      assert second_page.has_previous_page, "Expected second page to have a previous page"

      # Fetch the last page
      query = Search::Queries::CursorPaginatedRepoQuery.new(current_user: @admin, phrase: "sort:updated", per_page: 4, after: second_page.end_cursor)
      last_page = query_org_repos(query)

      assert_equal expected_repo_ids[8..9], last_page.results.map { |item| item["_id"].to_i }
      refute last_page.has_next_page, "Expected last page to not have a next page"
      assert last_page.has_previous_page, "Expected last page to have a previous page"
    end
  end

  def query_org_repos(query)
    query.qualifiers[:org].clear.must @org.display_login
    query.execute
  end
end
