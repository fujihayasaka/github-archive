# typed: true
# frozen_string_literal: true

require "test_helper"

class WorkspaceEditor::User::Dependency::Test < GitHub::TestCase

  setup do
    GitHub.flipper[:copilot_hadron_editor].enable
    @user = create(:user)
    create(:feature, :opt_out, slug: "copilot_hadron_editor")
    @user.enable_feature_preview(:copilot_hadron_editor)
    GitHub.flipper[:hadron_force_access].disable(@user)
  end

  test "returns false if the user does not have the feature preview enabled" do
    @user.disable_feature_preview(:copilot_hadron_editor)
    refute @user.workspace_editor_preview_enabled?
  end

  test "returns true if the user has the feature preview enabled and hadron_force_access" do
    GitHub.flipper[:hadron_force_access].enable(@user)
    assert @user.workspace_editor_preview_enabled?
  end

  test "returns false if the user doesn't have access to code review" do
    PullRequests::Copilot::CodeReviewAccess.any_instance.stubs(:can_create_review_request?).returns(false)
    refute @user.workspace_editor_preview_enabled?
  end

  test "returns false if no repository is passed" do
    PullRequests::Copilot::CodeReviewAccess.any_instance.stubs(:can_create_review_request?).returns(true)
    refute @user.workspace_editor_preview_enabled?
  end

  test "returns true if the user has access to code review on valid repo" do
    PullRequests::Copilot::CodeReviewAccess.any_instance.stubs(:can_create_review_request?).returns(true)
    assert @user.workspace_editor_preview_enabled?(repository: create(:repository, owner: @user))
  end
end
