# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventMetaEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @org_hook = create :hook, :org, events: %w(*)
    @repo_hook = create :hook, :web
    @business_hook = create :hook, installation_target: create(:business), events: %w(*)
  end

  test "required attributes" do
    assert_event_required_attributes(Hook::Event::MetaEvent, :hook_id, :action, :actor_id)
  end

  context "#hook" do
    test "is looked up using the hook_id" do
      event = Hook::Event::MetaEvent.new(action: :deleted, actor_id: 0, hook_id: @org_hook.id)

      assert_equal @org_hook, event.hook
    end
  end

  context "#subscribed_hooks" do
    test "only returns the hook it was triggered on when the hook is subscribed to meta events" do
      @org_hook.events = %w(meta)
      @org_hook.save!

      event = Hook::Event::MetaEvent.new(action: :deleted, actor_id: 0, hook_id: @org_hook.id)

      assert_equal [@org_hook], event.subscribed_hooks
    end

    test "only returns the hook it was triggered on when the hook is subscribed to * events" do
      event = Hook::Event::MetaEvent.new(action: :deleted, actor_id: 0, hook_id: @org_hook.id)

      assert_equal [@org_hook], event.subscribed_hooks
    end

    test "returns nothing when the hook it was triggered on is subscribed to something else" do
      @org_hook.events = %w(push)
      @org_hook.save!

      event = Hook::Event::MetaEvent.new(action: :deleted, actor_id: 0, hook_id: @org_hook.id)

      assert_empty event.subscribed_hooks
    end

    test "returns nothing when the hook cannot be found" do
      event = Hook::Event::MetaEvent.new(action: :deleted, actor_id: 0, hook_id: -1)

      assert_empty event.subscribed_hooks
    end
  end

  context "#target_repository" do
    test "returns nil if the hook is an org hook" do
      event = Hook::Event::MetaEvent.new(action: :deleted, actor_id: 0, hook_id: @org_hook.id)

      assert_nil event.target_repository
    end

    test "returns the repo if the hook is a repo hook" do
      event = Hook::Event::MetaEvent.new(action: :deleted, actor_id: 0, hook_id: @repo_hook.id)

      assert_equal @repo_hook.installation_target, event.target_repository
    end

    test "returns nil if the hook is a business hook" do
      event = Hook::Event::MetaEvent.new(action: :deleted, actor_id: 0, hook_id: @business_hook.id)

      assert_nil event.target_repository
    end
  end

  context "#target_organization" do
    test "returns nil if the hook is an repo hook" do
      event = Hook::Event::MetaEvent.new(action: :deleted, actor_id: 0, hook_id: @repo_hook.id)

      assert_nil event.target_organization
    end

    test "returns the org if the hook is an org hook" do
      event = Hook::Event::MetaEvent.new(action: :deleted, actor_id: 0, hook_id: @org_hook.id)

      assert_equal @org_hook.installation_target, event.target_organization
    end

    test "returns nil if the hook is a business hook" do
      event = Hook::Event::MetaEvent.new(action: :deleted, actor_id: 0, hook_id: @business_hook.id)

      assert_nil event.target_organization
    end
  end

  context "#target_business" do
    test "returns nil if the hook is an repo hook" do
      event = Hook::Event::MetaEvent.new(action: :deleted, actor_id: 0, hook_id: @repo_hook.id)

      assert_nil event.target_business
    end

    test "returns nil if the hook is an org hook" do
      event = Hook::Event::MetaEvent.new(action: :deleted, actor_id: 0, hook_id: @org_hook.id)

      assert_nil event.target_business
    end

    test "returns the business if the hook is a business hook" do
      event = Hook::Event::MetaEvent.new(action: :deleted, actor_id: 0, hook_id: @business_hook.id)

      assert_equal @business_hook.installation_target, event.target_business
    end
  end

  context "#actor" do
    test "returns the user found from actor_id" do
      user = create(:user)

      event = Hook::Event::MetaEvent.new(action: :deleted, actor_id: user.id, hook_id: @repo_hook.id)
      assert_equal user, event.actor
    end
  end
end
