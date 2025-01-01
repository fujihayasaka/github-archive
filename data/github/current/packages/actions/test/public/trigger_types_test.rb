# typed: true
# frozen_string_literal: true

require "github-launch"
require "test_helper"

class ActionsTriggerTypesTest < GitHub::TestCase
  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
    GitHub.stubs(:launch_github_app).returns(@github_app)
  end

  fixtures do
    GitHub.actions_enabled = true
    make_trusted_oauth_apps_owner
    @github_app = create(:launch_integration)
    GitHub.stubs(:launch_github_app).returns(@github_app)
    @owner       = create :user
    @repository  = create :private_repository, owner: @owner, from_example: :readmes

    @sha = @repository.heads.find("master").target_oid
    @check_suite = create :check_suite_for_actions_app, :with_push, repository: @repository, head_sha: @sha, name: "Test check suite"
    @workflow_run = @check_suite.workflow_run
    @workflow_run.update(trigger_id: @check_suite.push.id, trigger_type: @check_suite.push.class)
  end

  def setup
    @subject = Actions::TriggerTypes
  end

  context "call" do
    test "defines the correct trigger type with no retry" do
      type = @subject.call(
        workflow_run: @workflow_run
      )

      assert_equal Actions::TriggerTypes::PUSH, type
    end

    test "defines the correct trigger type with retry" do
      type = @subject.call(
        workflow_run: @workflow_run,
        triggered_by_retry: true
      )

      assert_equal Actions::TriggerTypes::RETRY, type
    end

    test "defines the correct trigger type using event" do
      @workflow_run.update(trigger_id: nil, trigger_type: nil, event: "merge_group", action: "checks_requested")

      type = @subject.call(
        workflow_run: @workflow_run
      )

      assert_equal Actions::TriggerTypes::MERGE_GROUP, type
    end

    test "correctly assigns OTHER as trigger with unknown trigger/event" do
      @workflow_run.update(trigger_id: nil, trigger_type: nil, event: "unknown", action: "unknown")

      type = @subject.call(
        workflow_run: @workflow_run
      )

      assert_equal Actions::TriggerTypes::OTHER, type
    end
  end
end
