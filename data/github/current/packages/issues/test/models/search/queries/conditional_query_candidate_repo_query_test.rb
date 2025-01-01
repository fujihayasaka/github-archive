# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesConditionalQueryCandidatePrivateRepoQueryTest < GitHub::TestCase
  fixtures do
    @monalisa = create(:user, login: "monalisa")
    @org      = create(:organization, login: "myorg")
    @team     = create(:team, organization: @org, privacy: :closed, name: "myteam")

    @team.add_member @monalisa

    @repo = create(:repository, name: "testrepo", owner: @org)

    @issue = create :issue, repository: @repo, user: @monalisa
  end

  setup do
    query = Search::Queries::ConditionalIssueQuery.new(phrase: "author:#{@monalisa.display_login}", current_user: @searcher)
    filtered_query = query.map_to_filters(query.conditional_qualifiers)
    @index =  Elastomer::Indexes::Issues.searcher("pull-requests")
    @query  = Search::Queries::ConditionalQueryCandidatePrivateRepoQuery.new(filtered_query, index: @index)
  end

  test "it searches for private repos in the query" do
    assert_includes @query.query_document[:query][:bool][:must],
    { term: { public: false } }
  end

  test "one filter passed in is used in the resulting query" do
    assert_includes @query.query_document[:query][:bool][:must],
                 { bool: { must: { term: { author_id: @monalisa.id } } } }
  end

  test "multiple filters passed in are used in the resulting query" do
    query = Search::Queries::ConditionalIssueQuery.new(phrase: "author:#{@monalisa.display_login} assignee:#{@monalisa.display_login}", current_user: @searcher)
    filtered_query = query.map_to_filters(query.conditional_qualifiers)

    query = Search::Queries::ConditionalQueryCandidatePrivateRepoQuery.new(filtered_query, index: @index)

    assert_includes query.query_document[:query][:bool][:must][0][:bool][:must],
                 { term: { author_id: @monalisa.id } }
    assert_includes query.query_document[:query][:bool][:must][0][:bool][:must],
                 { term: { assignee_id: @monalisa.id } }
  end

  test "index is correct when type isn't passed in" do
    assert_match "pull-requests", @query.index.name
  end

  test "size of query is set to 0" do
    assert_equal @query.query_document[:size], 0
  end

  test "aggregating on repo ids" do
    aggregations = @query.query_document[:aggregations]
    assert_equal aggregations[:repo_ids], { terms: { field: "repo_id", size: Search::Filters::RepositoryFilter::MAX_REPO_FILTER_SIZE } }
  end
end
