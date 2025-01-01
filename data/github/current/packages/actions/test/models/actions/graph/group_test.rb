# typed: true
# frozen_string_literal: true

require "test_helper"

class Actions::Graph::GroupTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    GitHub.stubs(:actions_enabled?).returns(true)
    make_trusted_oauth_apps_owner
    @github_app = create(:launch_integration)


    @repo = create(:public_repository)
    @check_suite = create(:check_suite_for_actions_app, repository: @repo)
    check_run_completed = create(:check_run, :success, check_suite: @check_suite, display_name: "build", parent_job_id: "build")
    @workflow_job_run_completed = check_run_completed.workflow_job_run

    check_run_completed2 = create(:check_run, :success, check_suite: @check_suite,  display_name: "build", parent_job_id: "build")
    @workflow_job_run_completed2 = check_run_completed2.workflow_job_run

    @single_job_group = Actions::Graph::Group.new(group: {
      id: "|-build-frontend-|test-A&test-B",
      jobs: [{
        id: "job-1"
      }, {
        id: "job-2"
      }],
      outputs: ["b"]
    }, workflow_job_runs: [@workflow_job_run_completed])

    @simple_group = Actions::Graph::Group.new(group: {
      id: "|-build-frontend-|test-A&test-B",
      jobs: [{
        id: "job-1"
      }, {
        id: "job-2"
      }],
      inputs: ["a"],
      outputs: ["b"]
    }, workflow_job_runs: [@workflow_job_run_completed])

    @matrix_group_single = Actions::Graph::Group.new(group: {
      id: "matrix-group",
      type: Actions::Graph::Group::GROUP_TYPE_MATRIX,
      jobs: [{
        name: "matrix-job"
      }],
      inputs: ["a"]
    }, workflow_job_runs: [@workflow_job_run_completed])
  end

  setup do
    GitHub.stubs(:launch_github_app).returns(@github_app)
  end

  test "has dom safe id" do
    assert_equal "group-_-build-frontend-_test-A_test-B", @simple_group.dom_id
  end

  test "maps inputs and outputs to safe ids" do
    assert_equal ["group-a"], @simple_group.inputs
    assert_equal ["group-b"], @simple_group.outputs
  end

  test "sets title for matrix group" do
    group = Actions::Graph::Group.new(group: {
      id: "matrix-group",
      type: Actions::Graph::Group::GROUP_TYPE_MATRIX,
      jobs: [{
        id: "matrix ID",
        name: "job name"
      }]
    }, workflow_job_runs: [])

    assert group.matrix?
    assert_equal "matrix ID", group.title
  end

  test "has nil parent_job_id for non-matrix group" do
    refute @simple_group.matrix?
    assert_nil @simple_group.parent_job_id
  end

  test "sets parent_job_id for matrix group" do
    group = Actions::Graph::Group.new(group: {
      id: "matrix-group",
      type: Actions::Graph::Group::GROUP_TYPE_MATRIX,
      jobs: [{
        id: "some-parent-id"
      }]
    }, workflow_job_runs: [])

    assert group.matrix?
    assert_equal "some-parent-id", group.parent_job_id
  end

  test "group conclusion is in progress when a single group is in progress" do
    check_run_in_progress = create(:check_run, :in_progress, check_suite: @check_suite, display_name: "build", parent_job_id: "build")

    matrix_group = Actions::Graph::Group.new(group: {
      id: "matrix-group",
      type: Actions::Graph::Group::GROUP_TYPE_MATRIX,
      jobs: [{
        name: "matrix-job"
      }],
      inputs: ["a"]
    }, workflow_job_runs: [@workflow_job_run_completed, @workflow_job_run_completed2, check_run_in_progress.workflow_job_run])

    assert matrix_group.matrix?
    assert matrix_group.in_progress?
    assert matrix_group.conclusion == "in_progress"
    assert_equal 2, matrix_group.completed_jobs_count
    assert_equal 3, matrix_group.jobs_count
  end

  test "group conclusion is nil when no jobs completed and no jobs are in progress" do
    check_run_queued = create(:check_run, :queued, check_suite: @check_suite,  display_name: "build", parent_job_id: "build")

    matrix_group = Actions::Graph::Group.new(group: {
      id: "matrix-group",
      type: Actions::Graph::Group::GROUP_TYPE_MATRIX,
      jobs: [{
        name: "matrix-job"
      }],
      inputs: ["a"]
    }, workflow_job_runs: [check_run_queued.workflow_job_run])

    assert matrix_group.matrix?
    assert !matrix_group.in_progress?
    assert matrix_group.conclusion.nil?
    assert_equal 0, matrix_group.completed_jobs_count
  end

  test "group conclusion is a success when all job are completed and succeed" do
    matrix_group = Actions::Graph::Group.new(group: {
      id: "matrix-group",
      type: Actions::Graph::Group::GROUP_TYPE_MATRIX,
      jobs: [{
        name: "matrix-job"
      }],
      inputs: ["a"]
    }, workflow_job_runs: [@workflow_job_run_completed, @workflow_job_run_completed2])

    assert matrix_group.matrix?
    assert !matrix_group.in_progress?
    assert matrix_group.conclusion == "success"
  end

  test "group conclusion is a failure when all job are completed and at least one failed" do
    check_run_completed_failed = create(:check_run, :failure, check_suite: @check_suite,  display_name: "build", parent_job_id: "build")

    matrix_group = Actions::Graph::Group.new(group: {
      id: "matrix-group",
      type: Actions::Graph::Group::GROUP_TYPE_MATRIX,
      jobs: [{
        name: "matrix-job"
      }],
      inputs: ["a"]
    }, workflow_job_runs: [@workflow_job_run_completed, @workflow_job_run_completed2, check_run_completed_failed.workflow_job_run])

    assert matrix_group.matrix?
    assert !matrix_group.in_progress?
    assert matrix_group.conclusion == "failure"
  end

  test "group conclusion rollup should follow the same logic as the check_suite " do
    check_run_completed_time_out = create(:check_run, :timed_out, check_suite: @check_suite,  display_name: "build", parent_job_id: "build")
    check_run_completed_failed = create(:check_run, :failure, check_suite: @check_suite,  display_name: "build", parent_job_id: "build")

    matrix_group = Actions::Graph::Group.new(group: {
      id: "matrix-group",
      type: Actions::Graph::Group::GROUP_TYPE_MATRIX,
      jobs: [{
        name: "matrix-job"
      }],
      inputs: ["a"]
    }, workflow_job_runs: [@workflow_job_run_completed, check_run_completed_time_out.workflow_job_run, check_run_completed_failed.workflow_job_run])

    assert matrix_group.matrix?
    assert !matrix_group.in_progress?
    assert matrix_group.conclusion == "timed_out"
    assert matrix_group.conclusion == @check_suite.conclusion
  end

  test "jobs sorting should give the same order as check_runs sorting for lexicographic edge case" do
    check_run_1 = create(:check_run, :success, check_suite: @check_suite,  display_name: "build-1", parent_job_id: "build-1")
    check_run_2 = create(:check_run, :success, check_suite: @check_suite,  display_name: "build-2", parent_job_id: "build-2")
    check_run_3 = create(:check_run, :success, check_suite: @check_suite,  display_name: "build-10", parent_job_id: "build-10")

    check_runs = [check_run_3, check_run_1, check_run_2]
    workflow_job_runs = [check_run_3.workflow_job_run, check_run_1.workflow_job_run, check_run_2.workflow_job_run]
    group = Actions::Graph::Group.new(group: {
      id: "|-build-frontend-|test-A&test-B",
      jobs: [{
        id: "build-10"
      }, {
        id: "build-1"
      }, {
        id: "build-2"
      }],
      inputs: ["a"],
      outputs: ["b"]
    }, workflow_job_runs: workflow_job_runs)

    assert_equal group.jobs.map(&:id), check_runs.sort_by(&:sort_order).map(&:display_name)
  end

  test "jobs sorting should give the same order for a simple case" do
    check_run_3 = create(:check_run, :success, check_suite: @check_suite,  display_name: "build-3", parent_job_id: "build-3")
    check_run_1 = create(:check_run, :success, check_suite: @check_suite,  display_name: "build-1", parent_job_id: "build-1")
    check_run_2 = create(:check_run, :success, check_suite: @check_suite,  display_name: "build-2", parent_job_id: "build-2")

    check_runs = [check_run_3, check_run_1, check_run_2]
    workflow_job_runs = [check_run_3.workflow_job_run, check_run_1.workflow_job_run, check_run_2.workflow_job_run]
    group = Actions::Graph::Group.new(group: {
      id: "|-build-frontend-|test-A&test-B",
      jobs: [{
        id: "build-1"
      }, {
        id: "build-3"
      }, {
        id: "build-2"
      }],
      inputs: ["a"],
      outputs: ["b"]
    }, workflow_job_runs: workflow_job_runs)

    assert_equal group.jobs.map(&:id), check_runs.sort_by(&:sort_order).map(&:display_name)
  end

  test "jobs sorting should give the same order even without check runs" do
    check_run_3 = create(:check_run, :success, check_suite: @check_suite,  display_name: "build-3", parent_job_id: "build-3")
    check_run_2 = create(:check_run, :success, check_suite: @check_suite,  display_name: "build-2", parent_job_id: "build-2")

    workflow_job_runs = [check_run_3.workflow_job_run, check_run_2.workflow_job_run]
    group = Actions::Graph::Group.new(group: {
      id: "|-build-frontend-|test-A&test-B",
      jobs: [{
        id: "build-1"
      }, {
        id: "build-3"
      }, {
        id: "build-2"
      }],
      inputs: ["a"],
      outputs: ["b"]
    }, workflow_job_runs: workflow_job_runs)

    assert_equal group.jobs.map(&:id), %w[build-1 build-2 build-3]
  end

  test "all check run statuses are present in STATUS_HIERARCHY" do
    assert_equal Actions::Graph::Group::STATUS_HIERARCHY.sort, CheckRun.statuses.keys.sort
  end

  test "all check run conclusions are present in CONCLUSIONS_HIERARCHY" do
    assert_equal Actions::Graph::Group::CONCLUSIONS_HIERARCHY.sort, CheckRun.conclusions.keys.sort
  end

  test "handles misssing check runs" do
    job = create(:check_run, :success, check_suite: @check_suite,  display_name: "build-1", parent_job_id: "build-1").workflow_job_run

    assert job.check_run.completed?
    job.check_run.delete # do not trigger callbacks

    job.reload

    group = Actions::Graph::Group.new(group: {
      id: "|-build-frontend-|test-A&test-B",
      jobs: [{
        id: "build-1"
      }],
      inputs: ["a"],
      outputs: ["b"]
    }, workflow_job_runs: [job])

    assert_equal 0, group.completed_jobs_count
    assert_equal "requested", group.status
    assert_nil group.conclusion
  end
end
