# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd::Mobile
  class NotifydWorkflowApprovalTest < GitHub::TestCase
    setup do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner
      @repository = create(:repository)
      @check_suite = create(
        :check_suite_for_actions_app,
        repository: @repository
      )
    end

    test "#render" do
      actor_login = "actor"
      renderer = WorkflowApprovalRenderer.new(
        workflow_run: @check_suite.workflow_run,
        repository: @repository,
        actor_login: actor_login,
      )
      layout = renderer.render

      action_run_id = @check_suite.workflow_run.run_number

      assert_equal "Deployment review in #{@repository.name_with_display_owner}", layout.title
      assert_match "#{actor_login} requested your review to deploy in \"#{@check_suite.name} \##{action_run_id}\"", layout.body
      assert_equal @check_suite.workflow_run.permalink, layout.url
      assert_equal @check_suite.workflow_run.permalink(include_host: false), layout.thread_id
      assert_equal "approval_requested", layout.thread_type
      assert_equal @check_suite.global_relay_id, layout.subject_id
    end
  end
end
