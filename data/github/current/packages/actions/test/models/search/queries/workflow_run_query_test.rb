# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesWorkflowRunQueryTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    GitHub.stubs(:actions_enabled?).returns(true)
    make_trusted_oauth_apps_owner

    @repo = create(:repository)
    @check_suite = create(:check_suite_for_actions_app, :failure, repository: @repo, name: "Node CI", event: "pull_request", action: "open")
    @workflow_run = @check_suite.workflow_run
    @actor = create(:user)
    @workflow_run.update(actor: @actor)
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
    @query = Search::Queries::WorkflowRunQuery.new(page: 1)
    GitHub::Experiment.raise_on_mismatches = false
  end

  context "query params" do
    test "it will only query workflow runs" do
      assert_equal({ type: "workflow_run" }, @query.query_params)
    end
  end

  context "when building the query" do
    test "it defaults to match_all" do
      assert_equal(
        { constant_score: { filter: { bool: { must: { term: { public: true } } } } } },
        @query.build_query,
      )
    end

    test "it creates a function score string query" do
      @query.phrase = "search"
      query = @query.build_query

      assert query[:bool][:must][:function_score][:query].key?(:query_string)

      qs = query[:bool][:must][:function_score][:query][:query_string]
      keys = [:query, :fields, :default_operator, :analyzer]
      keys.each { |key| assert qs.key?(key), "has key #{key.inspect}" }
      assert_equal keys.length, qs.keys.length
      assert_equal "search", qs[:query]
    end

    test "it queries the specified fields" do
      @query.phrase = "search status:queued"
      query = @query.build_query

      qs = query[:bool][:must][:function_score][:query][:query_string]
      assert_equal %w[name^1.2 status], qs[:fields]
    end

    test "builds a repo_id filter" do
      query = Search::Queries::WorkflowRunQuery.new(repo_id: @repo.id)
      assert_equal(
        { constant_score: { filter: { bool: { must: { term: { repo_id: @repo.id } } } } } }, query.build_query
      )
    end

    test "hiding spammy runs builds a user_hidden filter" do
      query = Search::Queries::WorkflowRunQuery.new(repo_id: @repo.id, hide_spammy_runs: true, show_spammy_runs_by_current_user: false)
      assert_equal(
        { constant_score: { filter: { bool: { must: [{ term: { repo_id: @repo.id } }, { term: { user_hidden: false } }] } } } }, query.build_query
      )
    end

    test "hiding spammy runs except ones by current user builds user_hidden and actor_id filters" do
      query = Search::Queries::WorkflowRunQuery.new(repo_id: @repo.id, hide_spammy_runs: true, show_spammy_runs_by_current_user: true, current_user: @actor)
      assert_equal(
        { constant_score: { filter: { bool: { must: { term: { repo_id: @repo.id } }, should: [{ term: { user_hidden: false } }, { term: { actor_id: @actor.id } }], minimum_should_match: 1 } } } }, query.build_query
      )
    end
  end

  context "when executing" do
    setup do # rubocop:disable GitHub/NestedSetupTeardown
      @response = {
        "took" => 445, "timed_out" => false, "_shards" => { "total" => 2, "successful" => 2, "failed" => 0 },
        "hits" => { "total" => 596, "max_score" => nil, "hits" => [
          {
            "_index" => "workflow-runs",
            "_type" => "workflow_run",
            "_id" => @workflow_run.id.to_s,
            "_score" => 3.9096773,
            "_source" => { "repo_id" => @repo.id, "name" => @workflow_run.name },
            "sort" => [1362070469000, 3.9096773],
          }]
        }
      }

      @index = Elastomer::Index.new("test")
      @response["hits"] = Elastomer::UpgradeShims.shim_search_response_hits(@response["hits"]) if @index.index_running_version_8_plus?
      @index.stubs(:search).returns(@response)
      @index.stubs(:count).returns(Elastomer::UpgradeShims.get_total_hits(@response["hits"]))

      @query.instance_variable_set(:@index, @index)
    end

    test "executes the query" do
      @query.phrase = "search"
      results = @query.execute

      assert_equal @query.page, results.page
      assert_equal @query.per_page, results.per_page
      assert_equal @response["took"], results.time
      assert_equal Elastomer::UpgradeShims.get_total_hits(@response["hits"]), results.total

      first = results.results.first
      assert first.is_a?(Hash)
      assert_equal @workflow_run, first["_model"]
    end

    test "tracks when no repository is set for the query" do
      @query.phrase = "search"
      @query.execute

      assert_dogstats_increment(1, "search.query.workflow_run.no_repo")
    end

    test "executes the count query" do
      @query.phrase = "search"
      assert_equal Elastomer::UpgradeShims.get_total_hits(@response["hits"]), @query.count
    end

    test "triggers update when workflow run spammy in ActiveRecord but not in ElasticSearch", skip_enterprise: true do
      # Add workflow run to ES then make user spammy
      check_suite = create(:check_suite_for_actions_app, repository: @repo)
      workflow_run = check_suite.workflow_run
      user = create(:user)
      workflow_run.update(actor: user)
      make_searchable(workflow_run)

      # Simulate updating the workflow_runs SQL table without commiting to ActiveRecord (which would trigger an ES update)
      Actions::WorkflowRun.any_instance.stubs(:user_hidden?).returns(true)

      GitHub.dogstats.expects(:increment).at_least_once
      GitHub.dogstats.expects(:increment).once.with("workflow_runs.user_hidden_out_of_sync")
      Search.expects(:add_to_search_index).with("workflow_run", workflow_run.id)

      workflow_runs_query = Search::Queries::WorkflowRunQuery.new(phrase: "check_suite_id:#{check_suite.id}", repo_id: @repo.id, current_user: user, hide_spammy_runs: true, show_spammy_runs_by_current_user: true)
      assert_equal 1, workflow_runs_query.count
      refute workflow_runs_query.execute.results.first["_source"]["user_hidden"]
    end

    # `head_branch` field mapping is configured as `"not_analyzed"` to only return EXACT matches.
    # see: `Elastomer::Indexes::WorkflowRuns`
    test "does exact match on branch name" do
      cs1 = create(:check_suite_for_actions_app, repository: @repo, head_branch: "main")
      cs1_fullref = create(:check_suite_for_actions_app, repository: @repo, head_branch: "refs/heads/main")
      cs2 = create(:check_suite_for_actions_app, repository: @repo, head_branch: "shouldnotmatchmaintest")
      cs3 = create(:check_suite_for_actions_app, repository: @repo, head_branch: "should-not-match-main-test")

      make_searchable(cs1.workflow_run)
      make_searchable(cs1_fullref.workflow_run)
      make_searchable(cs2.workflow_run)
      make_searchable(cs3.workflow_run)

      query = "branch:main"
      hash = {
        phrase: query,
        query: Search::Queries::WorkflowRunQuery.parse(query),
        repo_id: @repo.id
      }
      workflow_runs_query = Search::Queries::WorkflowRunQuery.new(hash)
      results = workflow_runs_query.execute.results

      assert_equal 2, results.count

      # ensure we get back the exact matching branch's workflow_run
      assert_same_elements [cs1.workflow_run.id, cs1_fullref.workflow_run.id], results.map { |r| r["_model"].id }
    end

    # `head_sha` field mapping is configured as `"not_analyzed"` to only return EXACT matches.
    # see: `Elastomer::Indexes::WorkflowRuns`
    test "does exact match on head_sha" do
      cs1 = create(:check_suite_for_actions_app, repository: @repo, head_sha: "d4a0f733b847f5bbb09adb56788a4")
      cs2 = create(:check_suite_for_actions_app, repository: @repo, head_sha: "c4a0f733b847f5bbb09adb56788a4")
      cs3 = create(:check_suite_for_actions_app, repository: @repo, head_sha: "e4kfj40dlwejfshwl4kdkslkhkg41")

      make_searchable(cs1.workflow_run)
      make_searchable(cs2.workflow_run)
      make_searchable(cs3.workflow_run)

      query = "head_sha:d4a0f733b847f5bbb09adb56788a4"
      hash = {
        phrase: query,
        query: Search::Queries::WorkflowRunQuery.parse(query),
        repo_id: @repo.id
      }
      workflow_runs_query = Search::Queries::WorkflowRunQuery.new(hash)
      results = workflow_runs_query.execute.results

      assert_equal 1, results.count

      # ensure we get back the exact matching head_sha's workflow_run
      assert_equal cs1.workflow_run.id, results.first["_model"].id
    end
  end
end
