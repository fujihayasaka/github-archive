# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventGollumEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @user = create(:user)
    @repo = create :repository, owner: @user
    @updates = [
      { action: :edited,  page_name: "home",  sha: "88d596906ef149c4e0fa4cd1b7c830193cfef3c2" },
    ]
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::GollumEvent, :actor_id, :repository_id, :updates
  end

  context "#repository" do
    test "returns the specified repository" do
      event = Hook::Event::GollumEvent.new actor_id: @user.id, repository_id: @repo.id, updates: @updates
      assert_equal @repo, event.repository
      assert_equal @repo, event.target_repository
    end

    test "returns nil on deleted repository" do
      @repo.remove(@user)
      event = Hook::Event::GollumEvent.new actor_id: @user.id, repository_id: @repo.id, updates: @updates
      assert_nil event.repository
      assert_nil event.target_repository
    end
  end

  context "#actor" do
    test "returns the specified user" do
      event = Hook::Event::GollumEvent.new actor_id: @user.id, repository_id: @repo.id, updates: @updates
      assert_equal @user, event.actor
    end
  end

  context "#deliverable?" do
    test "returns true when repository exist" do
      event = Hook::Event::GollumEvent.new actor_id: @user.id, repository_id: @repo.id, updates: @updates
      assert_predicate event, :deliverable?
    end

    test "returns false for a deleted repository" do
      @repo.destroy!
      event = Hook::Event::GollumEvent.new actor_id: @user.id, repository_id: @repo.id, updates: @updates
      refute_predicate event, :deliverable?
    end
  end
end
