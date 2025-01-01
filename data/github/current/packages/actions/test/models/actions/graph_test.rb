# typed: true
# frozen_string_literal: true

require "test_helper"

class Actions::GraphTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    make_trusted_oauth_apps_owner
    @github_app = create(:launch_integration)
    GitHub.stubs(:launch_github_app).returns(@github_app)
    @repo = create(:public_repository, owner: @user)
    @check_suite = create(:check_suite_for_actions_app, repository: @repo)
    @workflow_run = @check_suite.workflow_run
    check_run = create(:check_run, :success, check_suite: @check_suite)
    @workflow_job_run = check_run.workflow_job_run
  end

  setup do
    GitHub.stubs(:launch_github_app).returns(@github_app)

    @simple_graph_json = "{\"stages\":[{\"groups\":[{\"id\":\"|\",\"type\":0,\"jobs\":[{\"id\":\"build\"}],\"inputs\":null,\"outputs\":null}]}]}"
    @emoji_graph_json = "{\"stages\":[{\"groups\":[{\"id\":\"|\",\"type\":0,\"jobs\":[{\"id\":\"build🥑\"}],\"inputs\":null,\"outputs\":null}]}]}"
    @corrupted_graph_json = "{\"stages\":[{\"groups\":[{\"id\":\"|\",\"type\":0,\"jobs\":[{\"id\":\"build |"
    @no_stages_graph_json = "{\"groups\":[{\"id\":\"|\",\"type\":0,\"jobs\":[{\"id\":\"build🥑\"}],\"inputs\":null,\"outputs\":null}]}"
    @blank_graph_json = ""
  end

  context "initialization" do
    test "stores name and trigger" do
      graph = Actions::Graph.new(name: "name", trigger: "push", json: @simple_graph_json, workflow_job_runs: [@workflow_job_run])

      assert graph.is_valid?
      assert_equal "name", graph.name
      assert_equal "push", graph.trigger
    end

    test "parses stages" do
      graph = Actions::Graph.new(name: "name", trigger: "push", json: @simple_graph_json, workflow_job_runs: [@workflow_job_run])

      assert graph.is_valid?
      assert_equal 1, graph.stages.size
    end

    test "parses job with emoji" do
      graph = Actions::Graph.new(name: "name", trigger: "push", json: @emoji_graph_json, workflow_job_runs: [@workflow_job_run])

      assert graph.is_valid?
      assert_equal 1, graph.stages.size
      assert_equal 1, graph.stages.first.groups.first.jobs.size
    end

    test "parses blank graph" do
      graph = Actions::Graph.new(name: "name", trigger: "push", json: @blank_graph_json, workflow_job_runs: [@workflow_job_run])

      assert_equal false, graph.is_valid?
    end

    test "parses corrupted graph" do
      graph = Actions::Graph.new(name: "name", trigger: "push", json: @corrupted_graph_json, workflow_job_runs: [@workflow_job_run])

      refute graph.is_valid?
    end

    test "parses graph with no stages" do
      graph = Actions::Graph.new(name: "name", trigger: "push", json: @no_stages_graph_json, workflow_job_runs: [@workflow_job_run])

      refute graph.is_valid?
    end

    test "stages have groups" do
      graph = Actions::Graph.new(name: "name", trigger: "push", json: @simple_graph_json, workflow_job_runs: [@workflow_job_run])

      assert graph.is_valid?
      assert_equal 1, graph.stages.first.groups.size
    end

    test "groups have jobs " do
      graph = Actions::Graph.new(name: "name", trigger: "push", json: @simple_graph_json, workflow_job_runs: [@workflow_job_run])

      assert_equal 1, graph.stages.first.groups.first.jobs.size
    end

    test "check_runs are propagated properly" do
      build_check_run = create :check_run, :success, check_suite: @check_suite, display_name: "build"
      build_check_run.workflow_job_run.parent_job_id = "build"
      test_check_run = create :check_run, :success, check_suite: @check_suite, display_name: "test"
      test_check_run.workflow_job_run.parent_job_id = "test"

      graph_json = <<~JSON
        {"stages":[
          {"groups":[{"id":"|","type":0,"jobs":[{"id":"build"}],"inputs":null,"outputs":null}]},
          {"groups":[{"id":"|","type":0,"jobs":[{"id":"test"}],"inputs":null,"outputs":null}]}
        ]}
      JSON

      graph = Actions::Graph.new(name: "name", trigger: "push", json: graph_json, workflow_job_runs: [build_check_run.workflow_job_run, test_check_run.workflow_job_run])

      assert graph.is_valid?
      assert_equal build_check_run.id, graph.stages.first.groups.first.jobs.first.workflow_job_run.check_run.id
      assert_equal test_check_run.id, graph.stages.last.groups.first.jobs.first.workflow_job_run.check_run.id
    end
  end
end
