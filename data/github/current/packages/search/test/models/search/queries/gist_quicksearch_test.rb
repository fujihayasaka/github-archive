# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesGistQuicksearchTest < GitHub::TestCase
  fixtures do
    @defunkt = create(:staff_admin_user, login: "defunkt", plan: "medium", email: "chris@ozmm.org")
    @mojombo = create(:user, login: "mojombo", email: "tom@mojombo.com")

    @create_contents = [
      { name: "hello.rb", value: "def hello; puts 'Hello!'; end" },
    ]

    @defunkt_public_gist = GistHelpers.generate(user: @defunkt,
                                          public: true,
                                          contents: @create_contents,
                                          description: "Test Gist")
    @defunkt_secret_gist = GistHelpers.generate(user: @defunkt,
                                          public: false,
                                          contents: @create_contents,
                                          description: "Test Secret Gist")
    @mojombo_starred_gist = GistHelpers.generate(user: @mojombo,
                                          public: true,
                                          contents: @create_contents,
                                          description: "Test Starred Gist")

    @defunkt.star(@mojombo_starred_gist)
  end

  setup do
    @query = Search::Queries::GistQuicksearch.new(current_user: @defunkt)
  end

  context "query params" do
    test "it will only query repositories" do
      assert_equal("gist", @query.query_params[:type])
    end
  end

  context "when building the query" do
    test "scopes the query to only owned or starred gists" do
      expected = { constant_score: { filter: {
        bool: { must: [
          { terms: { gist_id: [@defunkt_secret_gist.id, @defunkt_public_gist.id, @mojombo_starred_gist.id].sort } },
          { term: { fork: false } },
          { exists: { field: :owner_id } },
        ] },
      } } }
      assert_equal expected, @query.build_query
    end

    test "it creates a function score string query for description" do
      @query.phrase = "search"
      query = @query.build_query

      assert query.key?(:bool)
      assert query[:bool][:must][:function_score]

      expected = {
        query: {
          match_phrase_prefix: {
            description: {
              query: "search",
              slop: 8,
              max_expansions: 10,
            },
          },
        },
        score_mode: "sum",
        functions: [
          { exp: { created_at: { scale: "42d", decay: 0.5 } } },
          { exp: { updated_at: { scale: "84d", decay: 0.5 } } },
        ],
      }

      actual = query[:bool][:must][:function_score]
      assert_equal expected, actual

      expected = { bool: { must: [
        { terms: { gist_id: [@defunkt_secret_gist.id, @defunkt_public_gist.id, @mojombo_starred_gist.id].sort } },
        { term: { fork: false } },
        { exists: { field: :owner_id } },
      ] } }
      assert_equal expected, query[:bool][:filter]
    end
  end

  context "when building the sort" do
    test "returns the default sort when the sort is empty" do
      assert_equal([{ "stars" => "desc" }, "_score"], @query.build_sort)

      @query.phrase = "\"\""
      assert_equal([{ "stars" => "desc" }, "_score"], @query.build_sort)
    end
  end

  test "query is invalid when user is logged out" do
    logged_out_query = Search::Queries::GistQuicksearch.new(current_user: nil)
    refute_predicate(logged_out_query, :valid_query?)
  end
end
