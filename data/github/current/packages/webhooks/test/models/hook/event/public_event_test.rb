# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventPublicEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @user = create(:user)
    @repo = create :repository, owner: @user
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::PublicEvent, :repo_id
  end

  context "#target_repository" do
    test "returns the specified repo" do
      event = Hook::Event::PublicEvent.new repo_id: @repo.id, actor_id: @user.id
      assert_equal @repo, event.target_repository
    end

    test "returns nil on deleted repository" do
      @repo.remove(@user)
      event = Hook::Event::PublicEvent.new repo_id: @repo.id, actor_id: @user.id
      assert_nil event.target_repository
    end
  end

  context "#actor" do
    test "returns the specified repo's owner" do
      event = Hook::Event::PublicEvent.new repo_id: @repo.id, actor_id: @user.id
      assert_equal @repo.owner, event.actor
    end
  end

  context "#deliverable?" do
    test "returns true when repository exist" do
      event = Hook::Event::PublicEvent.new repo_id: @repo.id, actor_id: @user.id
      assert_predicate event, :deliverable?
    end

    test "returns false for a deleted repository" do
      @repo.destroy!
      event = Hook::Event::PublicEvent.new repo_id: @repo.id, actor_id: @user.id
      refute_predicate event, :deliverable?
    end
  end
end
