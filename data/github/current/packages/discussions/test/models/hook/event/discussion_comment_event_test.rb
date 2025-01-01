# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventDiscussionCommentEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @user = create(:verified_user)
    @comment = create(:discussion_comment, user: @user)
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::DiscussionCommentEvent, :action, :comment_id, :actor_id
  end

  context "#comment" do
    test "returns the specified discussion comment" do
      event = Hook::Event::DiscussionCommentEvent.new(action: :created, comment_id: @comment.id, actor_id: @user.id)
      assert_equal @comment, event.comment
    end
  end

  context "#target_repository" do
    test "returns the repo of the specified comment" do
      event = Hook::Event::DiscussionCommentEvent.new(action: :created, comment_id: @comment.id, actor_id: @user.id)
      assert_equal @comment.repository, event.target_repository
    end
  end

  context "#actor" do
    test "returns the specified user" do
      event = Hook::Event::DiscussionCommentEvent.new(action: :created, comment_id: @comment.id, actor_id: @user.id)
      assert_equal @user, event.actor
    end
  end

  context "#changes" do
    test "returns nil if no changes were made" do
      event = Hook::Event::DiscussionCommentEvent.new(action: :created, comment_id: @comment.id, actor_id: @user.id)
      assert_nil event.changes
    end

    test "returns a hash with body changes if body changes were made" do
      event = Hook::Event::DiscussionCommentEvent.new(
        action: :edited,
        comment_id: @comment.id,
        actor_id: @user.id,
        changes: { old_body: "old body", body: "new body" },
      )
      expected_changes = { body: { from: "old body" } }
      assert_equal expected_changes, event.changes
    end
  end

  context "#deliverable?" do
    test "returns true when discussion and repository still exist" do
      event = Hook::Event::DiscussionCommentEvent.new(action: :created, comment_id: @comment.id, actor_id: @user.id)
      assert_predicate event, :deliverable?
    end

    test "returns false for deleted discussion" do
      event = Hook::Event::DiscussionCommentEvent.new(action: :created, comment_id: -1, actor_id: @user.id)
      refute_predicate event, :deliverable?
    end

    test "returns false for a deleted repository" do
      @comment.repository.destroy
      event = Hook::Event::DiscussionCommentEvent.new(action: :created, comment_id: @comment.id, actor_id: @user.id)
      refute_predicate event, :deliverable?
    end
  end
end
