# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventBranchProtectionConfigurationTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @org = create(:organization, plan: "business_plus")
    @org_repo = create(:repository, owner: @org)
    @actor = create(:collaborator, repository: @org_repo, action: :admin)
    @org_repo_hook = create :hook, :web, installation_target: @org_repo, events: %w(branch_protection_configuration)
    @org_hook = create :hook, :org, installation_target: @org, events: %w(branch_protection_configuration)
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::BranchProtectionConfigurationEvent, :action, :actor_id, :repository_id
  end

  context "#actor" do
    test "returns the user performing the action" do
      event = Hook::Event::BranchProtectionConfigurationEvent.new action: :enabled, actor_id: @actor.id, repository_id: @org_repo.id
      assert_equal @actor, event.actor
    end

    test "returns nil if the ID is invalid (e.g., user was deleted)" do
      actor_id = @actor.id
      @actor.destroy
      event = Hook::Event::BranchProtectionConfigurationEvent.new action: :enabled, actor_id: @actor.id, repository_id: @org_repo.id
      assert_nil event.actor
    end
  end

  context "#target_repository" do
    test "returns the repository the action was performed on" do
      event = Hook::Event::BranchProtectionConfigurationEvent.new action: :enabled, actor_id: @actor.id, repository_id: @org_repo.id
      assert_equal @org_repo, event.target_repository
    end
  end
end
