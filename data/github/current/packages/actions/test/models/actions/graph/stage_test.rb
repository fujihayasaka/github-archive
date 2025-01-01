# typed: true
# frozen_string_literal: true

require "test_helper"

class Actions::Graph::StageTest < GitHub::TestCase
  fixtures do
    make_trusted_oauth_apps_owner
    @github_app = create(:launch_integration)
    @repo = create(:public_repository)
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
    GitHub.stubs(:launch_github_app).returns(@github_app)
  end

  test "filter jobs by group" do
    check_suite = create(:check_suite_for_actions_app, repository: @repo)
    check_run1 = create(:check_run, :success, check_suite: check_suite, parent_job_id: "job1", display_name: "job 1")
    check_run2 = create(:check_run, :success, check_suite: check_suite, parent_job_id: "job2", display_name: "job 2")
    check_run3 = create(:check_run, :success, check_suite: check_suite, parent_job_id: "job3")
    check_run4 = create(:check_run, :success, check_suite: check_suite, parent_job_id: "job4")
    stage = Actions::Graph::Stage.new(stage: {
      groups: [{
        id: "|b",
        jobs: [{
          id: "job1"
        }, {
          id: "job2"
        }]
      },]
    }, workflow_job_runs: check_suite.check_runs.map { |check_run| check_run.workflow_job_run })

    job_names = stage.groups[0].jobs.map { |job| job.name }

    assert_equal 2, job_names.length
    assert job_names.include? check_run1.display_name
    assert job_names.include? check_run2.display_name
  end

  test "all called jobs with matrix grouped under caller job" do
    check_suite = create(:check_suite_for_actions_app, repository: @repo)
    check_run1 = create(:check_run, :success, check_suite: check_suite, parent_job_id: "matrix._1.called1", display_name: "matrix (1) / called1")
    check_run2 = create(:check_run, :success, check_suite: check_suite, parent_job_id: "matrix._2.called1", display_name: "matrix (2) / called1")
    check_run3 = create(:check_run, :success, check_suite: check_suite, parent_job_id: "matrix._1.called2", display_name: "matrix (1) / called2")
    check_run4 = create(:check_run, :success, check_suite: check_suite, parent_job_id: "matrix._2.called2", display_name: "matrix (2) / called2")
    stage = Actions::Graph::Stage.new(stage: {
      groups: [{
        id: "|-matrix-|",
        name: "matrix",
        type: Actions::Graph::Group::GROUP_TYPE_WORKFLOW_MATRIX,
        jobs: [{
          id: "matrix"
        }]
      }]
    }, workflow_job_runs: check_suite.check_runs.map { |check_run| check_run.workflow_job_run })

    job_names = stage.groups[0].matrix_jobs.map { |job| job.name }

    assert_equal 4, job_names.length
    assert job_names.include? check_run1.display_name
    assert job_names.include? check_run2.display_name
    assert job_names.include? check_run3.display_name
    assert job_names.include? check_run4.display_name
  end

  test "filter only the jobs that are in the called matrix" do
    check_suite = create(:check_suite_for_actions_app, repository: @repo)
    check_run1 = create(:check_run, :success, check_suite: check_suite, parent_job_id: "caller._1.called", display_name: "caller (1) / called")
    check_run2 = create(:check_run, :success, check_suite: check_suite, parent_job_id: "caller._2.called", display_name: "caller (2) / called")
    check_run3 = create(:check_run, :success, check_suite: check_suite, parent_job_id: "callerNoMatrix.called")
    check_run4 = create(:check_run, :success, check_suite: check_suite, parent_job_id: "other")
    stage = Actions::Graph::Stage.new(stage: {
      groups: [{
        id: "|-caller-|",
        name: "caller",
        type: Actions::Graph::Group::GROUP_TYPE_WORKFLOW_MATRIX,
        jobs: [{
          id: "caller"
        }]
      }]
    }, workflow_job_runs: check_suite.check_runs.map { |check_run| check_run.workflow_job_run })

    job_names = stage.groups[0].matrix_jobs.map { |job| job.name }

    assert_equal 2, job_names.length
    assert job_names.include? check_run1.display_name
    assert job_names.include? check_run2.display_name
  end
end
