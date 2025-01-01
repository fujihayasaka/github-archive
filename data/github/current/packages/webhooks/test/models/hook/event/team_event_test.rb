# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventTeamEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @owner = create(:user)
    @org = create(:organization, admin: @owner)
    @team = create :team, organization: @org
    @repo = create(:repository, owner: @org)
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::TeamEvent, :action, :team_id
  end

  test "to be required attributes" do
    assert_event_to_be_required_attributes Hook::Event::TeamEvent, :actor_id
  end

  context "#team" do
    test "returns the specified team" do
      event = Hook::Event::TeamEvent.new action: :created, team_id: @team.id, actor_id: @owner.id
      assert_equal @team, event.team
    end
  end

  context "#target_organization" do
    test "returns the organization of the specified team" do
      event = Hook::Event::TeamEvent.new action: :created, team_id: @team.id, actor_id: @owner.id
      assert_equal @team.organization, event.target_organization
    end
  end

  context "#target_repository" do
    test "returns the specified repo" do
      event = Hook::Event::TeamEvent.new action: :created, team_id: @team.id, actor_id: @owner.id, repo_id: @repo.id
      assert_equal @repo, event.target_repository
    end

    test "returns nil a on deleted repository" do
      @repo.remove(@user)
      event = Hook::Event::TeamEvent.new action: :created, team_id: @team.id, actor_id: @owner.id, repo_id: @repo.id
      assert_nil event.target_repository
    end
  end

  context "#actor" do
    test "returns the specified user" do
      event = Hook::Event::TeamEvent.new action: :created, team_id: @team.id, actor_id: @owner.id
      assert_equal @owner, event.actor
    end
  end

  context "#deliverable?" do
    test "returns true when repository and org exist" do
      event = Hook::Event::TeamEvent.new action: :created, team_id: @team.id, actor_id: @owner.id, repo_id: @repo.id
      assert_predicate event, :deliverable?
    end

    test "returns true for a deleted repository and the org exists" do
      @repo.destroy!
      event = Hook::Event::TeamEvent.new action: :created, team_id: @team.id, actor_id: @owner.id, repo_id: @repo.id
      assert_predicate event, :deliverable?
    end

    test "returns false when repository exist and the org is deleted" do
      @org.destroy!
      event = Hook::Event::TeamEvent.new action: :created, team_id: @team.id, actor_id: @owner.id, repo_id: @repo.id
      refute_predicate event, :deliverable?
    end

    test "returns false for a deleted repository and deleted org" do
      @org.destroy!
      @repo.destroy!
      event = Hook::Event::TeamEvent.new action: :created, team_id: @team.id, actor_id: @owner.id, repo_id: @repo.id
      refute_predicate event, :deliverable?
    end
  end
end
