# typed: true
# frozen_string_literal: true

require "test_helper"

class HierarchyCommands::PreloadTest < GitHub::TestCase
  include IssuesGraphTestHelpers
  include DogstatsTestHelpers
  include GitHub::LoggerHelper

  fixtures do
    @owner = create(:verified_user)

    @private_org = create(:organization, admin: @owner, plan: "business")
    @private_repo = create(:private_repository, owner: @private_org)
    @private_issue = create(:issue, repository: @private_repo)
  end

  setup do
    enable_feature_flag(:tasklist_block)
    enable_feature_flag(:issue_hierarchy_state)
  end

  test "when issue is a pull request, it returns a success result" do
    @private_issue.stubs(:pull_request?).returns(true)

    result = klass.new(
      issue: @private_issue,
      repository: @private_repo,
      owner: @owner,
      viewer: @owner
    ).call

    assert_predicate result, :success?
  end

  test "when the issue_hierarchy_state flag is disabled, it returns a failure result and raw hierarchy is fail result" do
    disable_feature_flag(:issue_hierarchy_state)

    result = klass.new(
      issue: @private_issue,
      repository: @private_repo,
      owner: @owner,
      viewer: @owner
    ).call

    refute_predicate result, :success?
    refute @private_issue.hierarchy_raw.success?
  end

  test "when the tasklist_block flag is disabled, it returns a failure result and raw hierarchy is fail result" do
    disable_feature_flag(:tasklist_block)

    result = klass.new(
      issue: @private_issue,
      repository: @private_repo,
      owner: @owner,
      viewer: @owner
    ).call

    refute_predicate result, :success?
    refute @private_issue.hierarchy_raw.success?
  end

  test "when the graph call is a success, it attaches the result to the issue and returns success" do
    # I am a bad person for this but I don't know how to make the async client
    # work in this test and it's late and I'm tired. :'(
    disable_feature_flag(:issues_graph_api_concurrent_faraday)
    mock_client = mock_issues_graph_client

    result = klass.new(
      issue: @private_issue,
      repository: @private_repo,
      owner: @owner,
      viewer: @owner,
      dependencies: {
        issues_graph_api_client: mock_client
      }
    ).call

    assert_predicate result, :success?
    assert @private_issue.hierarchy_raw.success?
  end

  test "when the graph call is a success, it checks if the markdown and issues graph are in sync" do
    # I am a bad person for this but I don't know how to make the async client
    # work in this test and it's late and I'm tired. :'(
    disable_feature_flag(:issues_graph_api_concurrent_faraday)
    mock_client = mock_issues_graph_client

    # In sync
    klass.new(
      issue: @private_issue,
      repository: @private_repo,
      owner: @owner,
      viewer: @owner,
      dependencies: {
        issues_graph_api_client: mock_client
      }
    ).call
    assert_predicate @private_issue, :hierarchy_synced?

    # Not in sync
    mock_client
      .stubs(:get_issue)
      .returns(
        build_get_issue_success_response(
          issue: build_proto_issue(timestamp: 10.minutes.ago.to_i),
        )
      )

    klass.new(
      issue: @private_issue,
      repository: @private_repo,
      owner: @owner,
      viewer: @owner,
      dependencies: {
        issues_graph_api_client: mock_client
      }
    ).call
    refute_predicate @private_issue, :hierarchy_synced?
  end

  test "stats when hierarchy_synced? is true, md at rest version" do
    disable_feature_flag(:issues_graph_api_concurrent_faraday)
    disable_feature_flag(:tasklist_block_precache)
    mock_client = mock_issues_graph_client

    klass.new(
      issue: @private_issue,
      repository: @private_repo,
      owner: @owner,
      viewer: @owner,
      dependencies: {
        issues_graph_api_client: mock_client
      }
    ).call

    assert_dogstats_increment(
      1,
      stats_key_synced,
      tags: [
        "synced:true",
        "pipeline_strategy:md-at-rest",
      ],
    )
  end

  test "stats when hierarchy_synced? is true, precache version" do
    disable_feature_flag(:issues_graph_api_concurrent_faraday)
    enable_feature_flag(:tasklist_block_precache)
    mock_client = mock_issues_graph_client

    klass.new(
      issue: @private_issue,
      repository: @private_repo,
      owner: @owner,
      viewer: @owner,
      dependencies: {
        issues_graph_api_client: mock_client
      }
    ).call

    assert_dogstats_increment(
      1,
      stats_key_synced,
      tags: [
        "synced:true",
        "pipeline_strategy:precache",
      ],
    )
  end

  test "stats when hierarchy_synced? is false, md-at-rest version" do
    disable_feature_flag(:issues_graph_api_concurrent_faraday)
    disable_feature_flag(:tasklist_block_precache)
    mock_client = mock_issues_graph_client

    # Not in sync
    mock_client
      .stubs(:get_issue)
      .returns(
        build_get_issue_success_response(
          issue: build_proto_issue(timestamp: 10.minutes.ago.to_i),
        )
      )

    klass.new(
      issue: @private_issue,
      repository: @private_repo,
      owner: @owner,
      viewer: @owner,
      dependencies: {
        issues_graph_api_client: mock_client
      }
    ).call

    assert_dogstats_increment(
      1,
      stats_key_synced,
      tags: [
        "synced:false",
        "pipeline_strategy:md-at-rest",
      ],
    )
  end

  test "stats when hierarchy_synced? is false, precache version" do
    disable_feature_flag(:issues_graph_api_concurrent_faraday)
    enable_feature_flag(:tasklist_block_precache)
    mock_client = mock_issues_graph_client

    # Not in sync
    mock_client
      .stubs(:get_issue)
      .returns(
        build_get_issue_success_response(
          issue: build_proto_issue(timestamp: 10.minutes.ago.to_i),
        )
      )

    klass.new(
      issue: @private_issue,
      repository: @private_repo,
      owner: @owner,
      viewer: @owner,
      dependencies: {
        issues_graph_api_client: mock_client
      }
    ).call

    assert_dogstats_increment(
      1,
      stats_key_synced,
      tags: [
        "synced:false",
        "pipeline_strategy:precache",
      ],
    )
  end

  test "stats when hierarchy_synced? is false, it logs md-at-rest version" do
    disable_feature_flag(:issues_graph_api_concurrent_faraday)
    disable_feature_flag(:tasklist_block_precache)
    mock_client = mock_issues_graph_client

    # Not in sync
    mock_client
      .stubs(:get_issue)
      .returns(
        build_get_issue_success_response(
          issue: build_proto_issue(timestamp: 10.minutes.ago.to_i),
        )
      )

    command = klass.new(
      issue: @private_issue,
      repository: @private_repo,
      owner: @owner,
      viewer: @owner,
      dependencies: {
        issues_graph_api_client: mock_client
      }
    )
    expected = {
      "Body" => "issue hierarchy not synced",
      "gh.repository_id" => @private_repo.id,
      "gh.issue_id" => @private_issue.id,
      "gh.issues_graph.pipeline_strategy" => "md-at-rest",
    }
    assert_logged(**expected) do
      command.call
    end
  end

  test "stats when hierarchy_synced? is false, it logs precache version" do
    disable_feature_flag(:issues_graph_api_concurrent_faraday)
    enable_feature_flag(:tasklist_block_precache)
    mock_client = mock_issues_graph_client

    # Not in sync
    mock_client
      .stubs(:get_issue)
      .returns(
        build_get_issue_success_response(
          issue: build_proto_issue(timestamp: 10.minutes.ago.to_i),
        )
      )

    command = klass.new(
      issue: @private_issue,
      repository: @private_repo,
      owner: @owner,
      viewer: @owner,
      dependencies: {
        issues_graph_api_client: mock_client
      }
    )
    expected = {
      "Body" => "issue hierarchy not synced",
      "gh.repository_id" => @private_repo.id,
      "gh.issue_id" => @private_issue.id,
      "gh.issues_graph.pipeline_strategy" => "precache",
    }
    assert_logged(**expected) do
      command.call
    end
  end

  test "when the graph call is a failure, it attaches the result to the issue and returns failure" do
    mock_client = mock_issues_graph_client
    mock_client.stubs(:get_issue).returns(IssuesGraph::Result.new(error: Struct.new(:message).new("error")))

    result = klass.new(
      issue: @private_issue,
      repository: @private_repo,
      owner: @owner,
      viewer: @owner,
      dependencies: {
        issues_graph_api_client: mock_client
      }
    ).call

    refute_predicate result, :success?
    refute @private_issue.hierarchy_raw.success?
  end

  test "it traces the call to issues graph" do
    mock_tracer = mock("tracer")

    mock_tracer.expects(:in_span).with("#call").once

    klass.new(
      issue: @private_issue,
      repository: @private_repo,
      owner: @owner,
      viewer: @owner,
      dependencies: {
        tracer: mock_tracer
      }
    ).call
  end

  test "it stats distribution timing" do
    klass.new(
      issue: @private_issue,
      repository: @private_repo,
      owner: @owner,
      viewer: @owner,
    ).call

    assert_dogstats_distribution(stats_key)
  end

  test "it makes one call to the issues graph when maybe_preload called many times" do
    mock_client = mock_async_issues_graph_client
    mock_client.expects(:get_issue)
      .times(1)
      .returns(Promise.resolve(IssuesGraph::Result.success({})))

    5.times do
      result = klass.async_maybe_preload(
        issue: @private_issue,
        repository: @private_repo,
        owner: @owner,
        viewer: @owner,
        dependencies: {
          async_issues_graph_api_client: mock_client
        }
      ).sync
      assert_predicate result, :success?
    end

    assert @private_issue.hierarchy_raw.success?
  end

  private

  def klass
    HierarchyCommands::Preload
  end

  def stats_key
    HierarchyCommands::Preload::STATS_KEY
  end

  def stats_key_synced
    HierarchyCommands::Preload::STATS_KEY_SYNCED
  end
end
