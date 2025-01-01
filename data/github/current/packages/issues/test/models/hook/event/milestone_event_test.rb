# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventMilestoneEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @user = create(:user)
    @repo = create :repository, owner: @user
    @milestone = create :milestone, repository: @repo, created_by: @repo.owner
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::MilestoneEvent, :action, :milestone_id, :actor_id
  end

  context "#milestone" do
    test "returns the specified milestone" do
      event = Hook::Event::MilestoneEvent.new action: :created, milestone_id: @milestone.id, actor_id: @user.id
      assert_equal @milestone, event.milestone
    end
  end

  context "#target_repository" do
    test "returns the repo of the specified user" do
      event = Hook::Event::MilestoneEvent.new action: :created, milestone_id: @milestone.id, actor_id: @user.id
      assert_equal @milestone.repository, event.target_repository
    end
  end

  context "#actor" do
    test "returns the specified user" do
      event = Hook::Event::MilestoneEvent.new action: :created, milestone_id: @milestone.id, actor_id: @user.id
      assert_equal @user, event.actor
    end
  end
end
