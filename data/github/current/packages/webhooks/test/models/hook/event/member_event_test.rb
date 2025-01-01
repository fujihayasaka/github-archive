# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventMemberEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @user = create(:user)
    @actor = create(:user)
    @repo = create(:repository)

    @event_attrs = {
      action: :added,
      repo_id: @repo.id,
      user_id: @user.id,
      actor_id: @actor.id,
    }
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::MemberEvent, :action, :actor_id, :repo_id, :user_id
  end

  context "#user" do
    test "returns the specified user" do
      event = Hook::Event::MemberEvent.new @event_attrs
      assert_equal @user, event.user
    end
  end

  context "#target_repository" do
    test "returns the specified repo" do
      event = Hook::Event::MemberEvent.new @event_attrs
      assert_equal @repo, event.target_repository
    end
  end

  context "#actor" do
    test "returns the actor if specified" do
      event = Hook::Event::MemberEvent.new @event_attrs.merge(actor_id: @actor.id)
      assert_equal @actor, event.actor
    end
  end

  context "#changes" do
    test "when no changes_attr it returns nil" do
      assert_nil Hook::Event::MemberEvent.new(@event_attrs).changes
    end

    test "when no permissions changes in changes_attr it returns nil" do
      data = @event_attrs.merge({ changes: {} })
      assert_nil Hook::Event::MemberEvent.new(data).changes
    end

    test "when permissions changes are in changes_attr it returns a permission hash" do
      data = @event_attrs.merge({
        changes: { old_permission: :write, new_permission: :admin }
      })
      expected = { from: :write, to: :admin }
      assert_equal expected,
        Hook::Event::MemberEvent.new(data).changes.dig(:permission)
    end

    test "when old permissions changes are in changes_attr it returns a `from` permission hash" do
      data = @event_attrs.merge({
        changes: { old_permission: :write }
      })
      expected = { from: :write }
      assert_equal expected,
        Hook::Event::MemberEvent.new(data).changes.dig(:permission)
    end

    test "when new permissions changes are in changes_attr it returns a `new` permission hash" do
      data = @event_attrs.merge({
        changes: { new_permission: :admin }
      })
      expected = { to: :admin }
      assert_equal expected,
        Hook::Event::MemberEvent.new(data).changes.dig(:permission)
    end

    test "when new_role_name changes are in changes_attr it returns a role_name permission hash" do
      data = @event_attrs.merge({
        changes: { new_role_name: :maintain }
      })
      expected = { to: :maintain }
      assert_equal expected,
        Hook::Event::MemberEvent.new(data).changes.dig(:role_name)
    end
  end
end
