# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesCandidatePrivateRepoQueryTest < GitHub::TestCase
  fixtures do
    @monalisa = create(:user, login: "monalisa")
    @org      = create(:organization, login: "myorg")
    @team     = create(:team, organization: @org, privacy: :closed, name: "myteam")

    @team.add_member @monalisa

    @repo = create(:repository, name: "testrepo", owner: @org)

    @issue = create :issue, repository: @repo, user: @monalisa
  end

  setup do
    @quals = Search::ParsedQuery.qualifiers
    @quals[:author].must "monalisa"

    @filter = Search::Filters::UserFilter.new(keys: :author, field: :author_id, qualifiers: @quals, exclude_private_profiles: false)
    @index =  Elastomer::Indexes::Issues.searcher("pull-requests")
    @query  = Search::Queries::CandidatePrivateRepoQuery.new({ author_id: @filter }, index: @index)
  end

  test "it searches for private repos in the query" do
    assert_includes @query.query_document[:query][:bool][:filter][:bool][:must],
    { term: { public: false } }
  end

  test "one filter passed in is used in the resulting query" do
    assert_includes @query.query_document[:query][:bool][:filter][:bool][:must],
                 { term: { author_id: @monalisa.id } }
  end

  test "multiple filters passed in are used in the resulting query" do
    quals = Search::ParsedQuery.qualifiers
    quals[:author].must             "monalisa"
    quals[:"review-requested"].must "monalisa"

    query = Search::Queries::CandidatePrivateRepoQuery.new({
      author_id: Search::Filters::UserFilter.new(keys: :author, field: :author_id, qualifiers: quals, exclude_private_profiles: false),
      requested_reviewer_ids: Search::Filters::UserFilter.new(keys: :"review-requested", field: :requested_reviewer_ids, qualifiers: quals, exclude_private_profiles: false)
    })

    assert_includes query.query_document[:query][:bool][:filter][:bool][:must],
                 { term: { author_id: @monalisa.id } }
    assert_includes query.query_document[:query][:bool][:filter][:bool][:must],
                 { term: { requested_reviewer_ids: @monalisa.id } }
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
