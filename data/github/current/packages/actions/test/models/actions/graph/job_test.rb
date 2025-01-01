# typed: true
# frozen_string_literal: true

require "test_helper"

class Actions::Graph::JobTest < GitHub::TestCase
  fixtures do
    GitHub.stubs(:actions_enabled?).returns(true)
    make_trusted_oauth_apps_owner
    @github_app = create(:launch_integration)

    @repo = create(:public_repository)
    @check_suite = create(:check_suite_for_actions_app, repository: @repo)
    check_run = create(:check_run, :success, check_suite: @check_suite, display_name: "Custom Name", parent_job_id: "build")
    @workflow_job_run = check_run.workflow_job_run

    @job = {
      id: "build",
      name: "name from launch"
    }
  end

  setup do
    GitHub.stubs(:launch_github_app).returns(@github_app)
  end

  context "#name" do
    test "prefers name from check run" do
      job = Actions::Graph::Job.new(job: @job, workflow_job_run: @workflow_job_run)

      assert_equal "Custom Name", job.name
    end

    test "falls back to static name" do
      job = Actions::Graph::Job.new(job: @job, workflow_job_run: nil)

      assert_equal "name from launch", job.name
    end

    test "falls back to id without name" do
      job = Actions::Graph::Job.new(job: {
        id: "build"
      }, workflow_job_run: nil)

      assert_equal "build", job.name
    end
  end
end
