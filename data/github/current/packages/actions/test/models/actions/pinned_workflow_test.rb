# typed: true
# frozen_string_literal: true

require "test_helper"

class Actions::PinnedWorkflowTest < GitHub::TestCase
  fixtures do
    @repository = create :repository
    @owner = @repository.owner
    @user = create(:user)
    @actions_app = create :launch_integration
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
  end

  test "create and delete pinned workflow" do
    workflow = create(:workflow, repository: @repository)
    pinned_workflow = Actions::PinnedWorkflow.create!(repository_id: @repository.id, workflow: workflow, pinned_by: @owner)

    assert_equal workflow, pinned_workflow.workflow
    assert_equal @owner, pinned_workflow.pinned_by
    assert_equal pinned_workflow, workflow.pinned_workflow

    # check that the pinned workflow is destroyed when workflow is destroyed
    workflow.destroy!
    refute Actions::PinnedWorkflow.exists?(pinned_workflow.id)
  end

  test "create max number of pinned workflow for a repository" do
    Actions::PinnedWorkflow.stub_const(:MAXIMUM_PINNED_WORKFLOWS, 1) do
      workflow = create(:workflow, repository: @repository)
      pinned_workflow = Actions::PinnedWorkflow.create!(repository_id: @repository.id, workflow: workflow, pinned_by: @owner)
      assert_equal workflow, pinned_workflow.workflow
      assert_equal @owner, pinned_workflow.pinned_by
      assert_equal pinned_workflow, workflow.pinned_workflow

      #make sure next one fails
      workflow = create(:workflow, repository: @repository)
      assert_raises(ActiveRecord::RecordInvalid) do
        Actions::PinnedWorkflow.create!(repository_id: @repository.id, workflow: workflow, pinned_by: @owner)
      end
    end
  end

  test "allow_pinning?" do
    enable_feature_flag(:actions_workflow_list_pinning, @repository)

    assert Actions::PinnedWorkflow.user_can_pin_workflows?(@repository, @owner)
    assert Actions::PinnedWorkflow.allow_pinning?(@repository, @owner)

    refute Actions::PinnedWorkflow.user_can_pin_workflows?(@repository, @user)
    refute Actions::PinnedWorkflow.allow_pinning?(@repository, @user)

    workflow = create(:workflow, repository: @repository)
    pinned_workflow = Actions::PinnedWorkflow.create!(repository_id: @repository.id, workflow: workflow, pinned_by: @owner)
    assert Actions::PinnedWorkflow.user_can_pin_workflows?(@repository, @owner)

    Actions::PinnedWorkflow.stub_const(:MAXIMUM_PINNED_WORKFLOWS, 1) do
      assert Actions::PinnedWorkflow.allow_pinning?(@repository, @owner)
    end
  end

  test "allow_pinning? returns false when flags are disabled" do
    disable_feature_flag(:actions_workflow_list_pinning, @repository)

    refute Actions::PinnedWorkflow.allow_pinning?(@repository, @owner)
    refute Actions::PinnedWorkflow.allow_pinning?(@repository, @user)
  end
end
