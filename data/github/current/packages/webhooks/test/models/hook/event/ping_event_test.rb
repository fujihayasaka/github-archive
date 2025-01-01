# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventPingEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @org_hook = create :hook, :org, events: %w(*)
    @repo_hook = create :hook, :web
    @repo_hook_without_creator = create :hook, :web, creator: nil
    @business_hook = create :hook, installation_target: create(:business), events: %w(*)
  end

  context "#hook_id" do
    test "is required" do
      assert_event_required_attributes Hook::Event::PingEvent, :hook_id
    end
  end

  context "#hook" do
    test "is looked up using the hook_id" do
      event = Hook::Event::PingEvent.new hook_id: @org_hook.id

      assert_equal @org_hook, event.hook
    end
  end

  context "#subscribed_hooks" do
    test "only returns the hook it was triggered on" do
      event = Hook::Event::PingEvent.new hook_id: @org_hook.id

      assert_equal [@org_hook], event.subscribed_hooks
    end
  end

  context "#target_repository" do
    test "returns nil if the hook is an org hook" do
      event = Hook::Event::PingEvent.new hook_id: @org_hook.id

      assert_nil event.target_repository
    end

    test "returns the repo if the hook is a repo hook" do
      event = Hook::Event::PingEvent.new hook_id: @repo_hook.id

      assert_equal @repo_hook.installation_target, event.target_repository
    end

    test "returns nil if the hook is a business hook" do
      event = Hook::Event::PingEvent.new hook_id: @business_hook.id

      assert_nil event.target_repository
    end
  end

  context "#target_organization" do
    test "returns nil if the hook is an repo hook" do
      event = Hook::Event::PingEvent.new hook_id: @repo_hook.id

      assert_nil event.target_organization
    end

    test "returns the org if the hook is an org hook" do
      event = Hook::Event::PingEvent.new hook_id: @org_hook.id

      assert_equal @org_hook.installation_target, event.target_organization
    end

    test "returns nil if the hook is a business hook" do
      event = Hook::Event::PingEvent.new hook_id: @business_hook.id

      assert_nil event.target_organization
    end
  end

  context "#target_business" do
    test "returns nil if the hook is an repo hook" do
      event = Hook::Event::PingEvent.new hook_id: @repo_hook.id

      assert_nil event.target_business
    end

    test "returns nil if the hook is an org hook" do
      event = Hook::Event::PingEvent.new hook_id: @org_hook.id

      assert_nil event.target_business
    end

    test "returns the business if the hook is a business hook" do
      event = Hook::Event::PingEvent.new hook_id: @business_hook.id

      assert_equal @business_hook.installation_target, event.target_business
    end
  end

  context "#actor" do
    test "returns the hook's creator if set" do
      event_with_actor = Hook::Event::PingEvent.new hook_id: @repo_hook.id
      assert_equal @repo_hook.creator, event_with_actor.actor

      event_without_actor = Hook::Event::PingEvent.new hook_id: @repo_hook_without_creator.id
      assert_nil event_without_actor.actor
    end
  end
end
