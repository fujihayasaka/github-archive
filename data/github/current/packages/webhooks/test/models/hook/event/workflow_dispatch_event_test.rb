# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventWorkflowDispatchEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @org = create(:organization)
    @user = create(:user)
    @repo = create :repository, owner: @org, from_example: :rebase_pull_request
    @repo.add_member @user

    @workflow_path = ".github/workflows/workflow.yml"
    @ref = @repo.default_branch_ref.qualified_name
  end

  test "require attributes" do
    assert_event_required_attributes Hook::Event::WorkflowDispatchEvent,
      :repository_id, :ref, :actor_id, :workflow
  end

  context "#workflow" do
    test "returns the specified workflow path" do
      event = Hook::Event::WorkflowDispatchEvent.new repository_id: @repo.id, ref: @ref, workflow: @workflow_path, actor_id: @user.id
      assert_equal @workflow_path, event.workflow
    end
  end

  context "#inputs" do
    test "returns the specified inputs" do
      event = Hook::Event::WorkflowDispatchEvent.new repository_id: @repo.id, ref: @ref, workflow: @workflow_path, inputs: { "name": "monalisa" }, actor_id: @user.id
      assert_equal ({ "name": "monalisa" }), event.inputs
    end
  end

  context "#target_repository" do
    test "returns the repo of the specified workflow dispatch" do
      event = Hook::Event::WorkflowDispatchEvent.new repository_id: @repo.id, ref: @ref, workflow: @workflow_path, actor_id: @user.id
      assert_equal @repo, event.target_repository
    end

    test "returns nil on deleted repository" do
      @repo.remove(@user)
      event = Hook::Event::WorkflowDispatchEvent.new repository_id: @repo.id, ref: @ref, workflow: @workflow_path, actor_id: @user.id
      assert_nil event.target_repository
    end
  end

  context "#actor" do
    test "returns the actor of the specified actor_id" do
      event = Hook::Event::WorkflowDispatchEvent.new repository_id: @repo.id, ref: @ref, workflow: @workflow_path, actor_id: @user.id
      assert_equal @user, event.actor
    end
  end

  context "#deliverable?" do
    test "returns true when repository exist" do
      event = Hook::Event::WorkflowDispatchEvent.new repository_id: @repo.id, ref: @ref, workflow: @workflow_path, actor_id: @user.id
      assert_predicate event, :deliverable?
    end

    test "returns false for a deleted repository" do
      @repo.destroy!
      event = Hook::Event::WorkflowDispatchEvent.new repository_id: @repo.id, ref: @ref, workflow: @workflow_path, actor_id: @user.id
      refute_predicate event, :deliverable?
    end
  end
end
