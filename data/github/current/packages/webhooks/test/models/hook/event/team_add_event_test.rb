# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventTeamAddEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @org = create(:organization)
    @team = create :team, organization: @org
    @org_repo = create :repository, owner: @org

  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::TeamAddEvent, :team_id, :repository_id
  end

  context "#target_repository" do
    test "returns the secified repo" do
      event = Hook::Event::TeamAddEvent.new team_id: @team.id, repository_id: @org_repo.id
      assert_equal @org_repo, event.target_repository
    end
  end

  context "#team" do
    test "returns the secified team" do
      event = Hook::Event::TeamAddEvent.new team_id: @team.id, repository_id: @org_repo.id
      assert_equal @team, event.team
    end
  end

  context "#actor" do
    test "returns the organization the team is in" do
      event = Hook::Event::TeamAddEvent.new team_id: @team.id, repository_id: @org_repo.id
      assert_equal @org, event.actor
    end
  end

  context "#deliverable?" do
    test "is true when the target_repository is present" do
      event = Hook::Event::TeamAddEvent.new team_id: @team.id, repository_id: @org_repo.id

      assert_predicate event, :deliverable?
    end

    test "is false when the target_repository is not present" do
      event = Hook::Event::TeamAddEvent.new team_id: @team.id, repository_id: -1

      refute_predicate event, :deliverable?
    end
  end
end
