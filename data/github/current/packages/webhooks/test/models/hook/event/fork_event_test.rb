# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventForkEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @repo = create(:repository)
    @fork = create :repository, parent: @repo
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::ForkEvent, :fork_repository_id
  end

  context "#fork_repository" do
    test "returns the specified fork" do
      event = Hook::Event::ForkEvent.new fork_repository_id: @fork.id
      assert_equal @fork, event.fork_repository
    end

    test "return nil on deleted repository" do
      @fork.remove(@user)
      event = Hook::Event::ForkEvent.new fork_repository_id: @fork.id
      assert_nil event.fork_repository
    end
  end

  context "#parent_repository" do
    test "returns the parent of the specified fork" do
      event = Hook::Event::ForkEvent.new fork_repository_id: @fork.id
      assert_equal @repo, event.parent_repository
    end

    test "returns nil on deleted fork repository" do
      @fork.remove(@user)
      event = Hook::Event::ForkEvent.new fork_repository_id: @fork.id
      assert_nil event.parent_repository
    end
  end

  context "#target_repository" do
    test "returns the parent of the specified fork" do
      event = Hook::Event::ForkEvent.new fork_repository_id: @fork.id
      assert_equal @repo, event.target_repository
    end

    test "returns nil on deleted repository" do
      @fork.remove(@user)
      event = Hook::Event::ForkEvent.new fork_repository_id: @fork.id
      assert_nil event.target_repository
    end
  end

  context "#actor" do
    test "returns the owner of the specified fork" do
      event = Hook::Event::ForkEvent.new fork_repository_id: @fork.id
      assert_equal @fork.owner, event.actor
    end
  end

  context "#deliverable?" do
    test "returns true when repository exist" do
      event = Hook::Event::ForkEvent.new fork_repository_id: @fork.id
      assert_predicate event, :deliverable?
    end

    test "returns false for a deleted repository" do
      @fork.destroy!
      event = Hook::Event::ForkEvent.new fork_repository_id: @fork.id
      refute_predicate event, :deliverable?
    end
  end
end
