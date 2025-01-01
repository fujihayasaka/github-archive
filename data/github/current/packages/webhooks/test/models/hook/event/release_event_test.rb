# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventReleaseEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @user = create(:user)
    @repo = create :repository, owner: @user, from_example: :repository_test_simple

    # Contains tags 'v1' and 'v2'

    @release = create :release, repository: @repo, author: @user, tag_name: "v1", actor: @user
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::ReleaseEvent, :release_id, :action, :actor_id
  end

  context "#release" do
    test "returns the specified release" do
      event = Hook::Event::ReleaseEvent.new release_id: @release.id, action: :published, actor_id: @user.id
      assert_equal @release, event.release
    end
  end

  context "#target_repository" do
    test "returns the repo of the specified release" do
      event = Hook::Event::ReleaseEvent.new release_id: @release.id, action: :published, actor_id: @user.id
      assert_equal @repo, event.target_repository
    end
  end

  context "#actor" do
    test "returns the author of the specified release" do
      event = Hook::Event::ReleaseEvent.new release_id: @release.id, action: :published, actor_id: @user.id
      assert_equal @user, event.actor
    end
  end

  context "#deliver" do
    test "handles deleted release" do
      event = Hook::Event::ReleaseEvent.new release_id: @release.id, action: :published, actor_id: @user.id
      @release.destroy

      assert_nil event.target_repository
      event.deliver
    end
  end

  context "#changes" do
    test "returns nil when there are no changes" do
      event = Hook::Event::ReleaseEvent.new release_id: @release.id, action: :edited, actor_id: @user.id, changes: nil
      assert_nil event.changes
    end

    test "returns a formatted hash when the name has changed" do
      event = Hook::Event::ReleaseEvent.new release_id: @release.id, action: :edited, actor_id: @user.id, changes: { old_name: "v0.0.1" }
      assert_equal({ name: { from: "v0.0.1" } }, event.changes)
    end

    test "returns a formatted hash when the body has changed" do
      event = Hook::Event::ReleaseEvent.new release_id: @release.id, action: :edited, actor_id: @user.id, changes: { old_body: "Tpyo" }
      assert_equal({ body: { from: "Tpyo" } }, event.changes)
    end

    test "returns a formatted hash when the release has been marked as latest" do
      event = Hook::Event::ReleaseEvent.new release_id: @release.id, action: :edited, actor_id: @user.id, changes: { make_latest: true }
      assert_equal({ make_latest: { to: true } }, event.changes)
    end
  end

  context "#deliverable?" do
    test "returns true when the target_repository is present" do
      event = Hook::Event::ReleaseEvent.new release_id: @release.id, action: :published, actor_id: @user.id
      assert event.deliverable?
    end
  end
end
