# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventPushEventTest < GitHub::TestCase
  include HookEventTestHelper

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @org = create(:organization)
    @repo = create :repository, owner: @org
    @repo_hook = create :hook, :web, installation_target: @repo
    @org_hook = create :hook, :org, installation_target: @org

    @attrs = {
      repo: @repo,
      before: "0000000000000000000000000000000000000000",
      after: "c1800491d95c42b4e96fb83f31fe8d9230c62907",
      ref: "refs/heads/my-branch",
    }
  end

  context "required attributes:" do
    test "repo is required" do
      error = assert_raises Hook::Event::MissingRequiredAttribute do
        Hook::Event::PushEvent.new @attrs.merge(repo: nil)
      end

      assert_includes error.message, "repo"
    end

    test "before is required" do
      error = assert_raises Hook::Event::MissingRequiredAttribute do
        Hook::Event::PushEvent.new @attrs.merge(before: nil)
      end

      assert_includes error.message, "before"
    end

    test "after is required" do
      error = assert_raises Hook::Event::MissingRequiredAttribute do
        Hook::Event::PushEvent.new @attrs.merge(after: nil)
      end

      assert_includes error.message, "after"
    end

    test "ref is required" do
      error = assert_raises Hook::Event::MissingRequiredAttribute do
        Hook::Event::PushEvent.new @attrs.merge(ref: nil)
      end

      assert_includes error.message, "ref"
    end
  end

  context "#pusher" do
    test "returns nil if pusher is not provided" do
      event = Hook::Event::PushEvent.new @attrs.merge(pusher: nil)
      assert_nil event.pusher
    end

    test "returns the user if pusher is provided" do
      event = Hook::Event::PushEvent.new @attrs.merge(pusher: @repo.owner)
      assert_equal @repo.owner, event.pusher
    end
  end

  context "#actor" do
    test "returns nil if pusher is not provided" do
      event = Hook::Event::PushEvent.new @attrs.merge(pusher: nil)
      assert_nil event.actor
    end

    test "returns the pusher if pusher is provided" do
      event = Hook::Event::PushEvent.new @attrs.merge(pusher: @repo.owner)
      assert_equal @repo.owner, event.actor
    end
  end

  context "#subscribed_hooks" do
    test "includes all repo hooks if target_hook_id is not supplied" do
      event = Hook::Event::PushEvent.new(@attrs)

      assert_equal 2, event.subscribed_hooks.count
      assert_includes event.subscribed_hooks, @repo_hook
      assert_includes event.subscribed_hooks, @org_hook
    end

    test "only includes the target hook if supplied" do
      event = Hook::Event::PushEvent.new(@attrs.merge(target_hook: @org_hook))

      assert_equal 1, event.subscribed_hooks.count
      refute_includes event.subscribed_hooks, @repo_hook
      assert_includes event.subscribed_hooks, @org_hook
    end
  end

  context "#deliverable?" do
    test "is true when the target_repository is present" do
      event = Hook::Event::PushEvent.new(@attrs)

      assert_predicate event, :deliverable?
    end

    test "is false when the target_repository is not present" do
      Hook::Event::PushEvent.any_instance.stubs(:target_repository).returns(nil)
      event = Hook::Event::PushEvent.new(@attrs)

      refute_predicate event, :deliverable?
    end
  end
end
