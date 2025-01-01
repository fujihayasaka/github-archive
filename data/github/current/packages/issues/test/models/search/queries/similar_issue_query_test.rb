# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesSimilarIssueQueryTest < GitHub::TestCase
  fixtures do
    @defunkt = create(:staff_admin_user, login: "defunkt", plan: "medium", email: "chris@ozmm.org")
    @mojombo = create(:user, login: "mojombo", email: "tom@mojombo.com")
    @org = create(:organization, login: "myorg")
    @team = create(:team, organization: @org, privacy: :closed, name: "myteam")
    @team.add_member @defunkt
    @team.add_member @mojombo

    @facebox = create(:repository, name: "facebox", owner: @defunkt)
    @grit = create(:repository, name: "grit", owner: @mojombo)

  end

  setup do
    @query = Search::Queries::SimilarIssueQuery.new(current_user: @defunkt)
    GitHub::Experiment.raise_on_mismatches = false
  end

  context "query params" do
    test "it will query issues only" do
      query_params = @query.query_params
      assert_equal({}, query_params)
      assert_match "issues-test", @query.index.name
    end

    test "even with pull requests set" do
      @query.phrase = "type:pr"
      query_params = @query.query_params
      assert_equal({}, query_params)
      assert_match "issues-test", @query.index.name
    end

    test "ignores invalid types" do
      @query.phrase = "type:trollololol"
      query_params = @query.query_params
      assert_equal({}, query_params)
      assert_match "issues-test", @query.index.name
    end

    test "even with explicit override" do
      query = Search::Queries::SimilarIssueQuery.new(current_user: @defunkt, type: "pr", phrase: "type:issue")
      query_params = query.query_params
      assert_equal({}, query_params)
      assert_match "issues-test", query.index.name
    end

    test "generates routing information" do
      @query.phrase = "search @defunkt @mojombo/grit"
      query_params = @query.query_params
      assert_equal({ routing: "#{@grit.id},#{@facebox.id}" }, @query.query_params)
      assert_match "issues-test", @query.index.name
    end
  end

  context "when building the query" do
    test "empty queries only match public repos" do
      expected = { constant_score: { filter: { bool: { must: { term: { public: true } } } } } }
      assert_equal expected, @query.build_query
    end
  end

  context "when building the highlight" do
    test "it does not create highlighting" do
      assert_nil @query.build_highlight
    end
  end

  context "when building the sort" do
    test "returns sort by created_at when the sort is empty and a query is present" do
      @query.query = "foo"
      assert_nil @query.build_sort
    end

    test "returns the default sort when the sort is empty" do
      @query.phrase = '""'
      assert_nil @query.build_sort
    end
  end

  context "when building the aggregations" do
    test "does not include a language filter" do
      @query.aggregations = true
      @query.phrase = "language:ruby"

      assert_nil @query.build_aggregations
    end
  end

  context "when created with a repository id" do
    test "overrides the normal repository filter" do
      query = Search::Queries::SimilarIssueQuery.new(phrase: "search @defunkt -@mojombo", repo_id: @grit.id)

      expected = {
        bool: {
          must: {
            multi_match: {
              query: "search",
              fields: ["title^1.5", "body"],
            },
          },
          filter: {
            bool: {
              must: {
                term: { repo_id: @grit.id },
              },
            },
          },
        },
      }

      assert_equal expected, query.build_query
    end
  end
end
