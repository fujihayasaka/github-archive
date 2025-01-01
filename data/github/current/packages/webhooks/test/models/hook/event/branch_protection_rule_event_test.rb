# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventBranchProtectionRuleTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @user = create(:user)
    @repo = create :repository, owner: @user

    @actor = create(:user)

    @owner = create(:user)
    @repo = create :repository, created_by_user_id: nil, owner: @owner

    @rule = create(:protected_branch, {
      repository: @repo,
      creator: @owner,
      name: "*",
    })
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::BranchProtectionRuleEvent, :action, :protected_branch_id, :actor_id
  end

  context "#actor" do
    test "returns the user performing the action" do
      event = Hook::Event::BranchProtectionRuleEvent.new action: :foo, protected_branch_id: 123, actor_id: @actor.id
      assert_equal @actor, event.actor
    end

    test "returns nil if the ID is invalid (e.g., user was deleted)" do
      actor_id = @actor.id
      @actor.destroy
      event = Hook::Event::BranchProtectionRuleEvent.new action: :foo, protected_branch_id: @rule.id, actor_id: actor_id
      assert_nil event.actor
    end
  end

  context "#protected_branch" do
    test "returns the protected_branch entity matching the rule" do
      event = Hook::Event::BranchProtectionRuleEvent.new action: :foo, protected_branch_id: @rule.id, actor_id: 123
      assert_equal @rule, event.protected_branch
    end
  end

  context "#target_repository" do
    test "returns the rule's repository" do
      event = Hook::Event::BranchProtectionRuleEvent.new action: :foo, protected_branch_id: @rule.id, actor_id: 123
      assert_equal @repo, event.target_repository
    end
  end

  context "#deliverable?" do
    test "returns true when repository and rule still exist" do
      event = Hook::Event::BranchProtectionRuleEvent.new action: :foo, protected_branch_id: @rule.id, actor_id: 123
      assert_predicate event, :deliverable?
    end

    test "returns false for deleted rule" do
      event = Hook::Event::BranchProtectionRuleEvent.new action: :foo, protected_branch_id: -1, actor_id: 123
      refute_predicate event, :deliverable?
    end

    test "returns false for a deleted repository" do
      @repo.destroy!
      event = Hook::Event::BranchProtectionRuleEvent.new action: :foo, protected_branch_id: @rule.id, actor_id: 123
      refute_predicate event, :deliverable?
    end
  end
end
