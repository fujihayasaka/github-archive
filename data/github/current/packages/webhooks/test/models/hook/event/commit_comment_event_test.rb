# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventCommitCommentEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @user = create(:user)
    @commit_comment = create :commit_comment, user: @user
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::CommitCommentEvent, :action, :commit_comment_id
  end

  context "#commit_comment" do
    test "returns the specified commit comment" do
      event = Hook::Event::CommitCommentEvent.new action: :created, commit_comment_id: @commit_comment.id
      assert_equal @commit_comment, event.commit_comment
    end
  end

  context "#target_repository" do
    test "returns the repo of the specified commit comment" do
      event = Hook::Event::CommitCommentEvent.new action: :created, commit_comment_id: @commit_comment.id
      assert_equal @commit_comment.repository, event.target_repository
    end
  end

  context "#actor" do
    test "returns the author of the specified commit comment" do
      event = Hook::Event::CommitCommentEvent.new action: :created, commit_comment_id: @commit_comment.id
      assert_equal @commit_comment.user, event.actor
    end
  end

  context "#deliver" do
    test "handles deleted comment" do
      event = Hook::Event::CommitCommentEvent.new action: :created, commit_comment_id: @commit_comment.id
      @commit_comment.destroy

      assert_nil event.target_repository
      event.deliver
    end
  end
end
