# typed: true
# frozen_string_literal: true

require "test_helper"

class CreateActionsAnnotationsJobTest < GitHub::TestCase
  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
  end

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @repository = create(:repository)

    make_trusted_oauth_apps_owner

    @check_suite = create(:check_suite_for_actions_app, repository: @repository)
    @check_run = create(:check_run_for_actions_app, check_suite: @check_suite, repository: @repository)
    @workflow_run = @check_suite.workflow_run

    @workflow_run_to_delete = create(:check_suite_for_actions_app, repository: @repository).workflow_run

    @second_check_suite = create(:check_suite_for_actions_app, repository: @repository)
    @second_workflow_run = @second_check_suite.workflow_run
    @check_run_to_delete = create(:check_run_for_actions_app, check_suite: @second_check_suite, repository: @repository)
    @job_id = @check_run.external_id
    @second_job_id = @check_run_to_delete.external_id
    @message = "Your workflow is using a version of actions/cache that is scheduled for deprecation."
    @warning_level = "warning"
  end

  context CreateActionsAnnotationsJob, skip_enterprise: true do
    test "creates annotation on check_run" do
      assert_difference "CheckAnnotation.count", 1 do
        CreateActionsAnnotationsJob.perform_now(repo_id: @repository.id, workflow_run_id: @workflow_run.id, job_id: @job_id, message: @message, warning_level: @warning_level)
      end

      created_annotation = CheckAnnotation.last!
      assert_equal @repository.id, created_annotation.repository_id
      assert_equal @check_run.id, created_annotation.check_run_id
      assert_equal @warning_level, created_annotation.warning_level
      assert_equal @message, created_annotation.message
      assert_equal CheckAnnotation::ACTIONS_SYSTEM_PATH, created_annotation.filename
    end

    test "Background Job does not run when one of the required fields is missing" do
      assert_no_difference "CheckAnnotation.count" do
        CreateActionsAnnotationsJob.perform_now(repo_id: @repository.id, workflow_run_id: @workflow_run.id, job_id: nil, message: @message, warning_level: @warning_level)
      end
    end
    test "Background Job does not run when the workflow_run isn't found" do
      workflow_run_id = @workflow_run_to_delete.id
      @workflow_run_to_delete.destroy
      assert_no_difference "CheckAnnotation.count" do
        CreateActionsAnnotationsJob.perform_now(repo_id: @repository.id, workflow_run_id: workflow_run_id, job_id: @job_id, message: @message, warning_level: @warning_level)
      end
    end
    test "Background Job does not run when the check_run isn't found" do
      @check_run_to_delete.destroy
      assert_no_difference "CheckAnnotation.count" do
        CreateActionsAnnotationsJob.perform_now(repo_id: @repository.id, workflow_run_id: @second_workflow_run.id, job_id: @second_job_id, message: @message, warning_level: @warning_level)
      end
    end
  end
end
