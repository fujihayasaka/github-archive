# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionCommentCreatorTest < GitHub::TestCase
  fixtures do
    @user       = create(:verified_user)
    @discussion = create(:discussion, user: @user)
    @comment    = create(:discussion_comment, discussion: @discussion)
  end

  context "#save" do
    test "creates a new top level comment" do
      body = "check out this awesome TWICE performance! https://youtube.com/watch?v=N11ZIDwwW24"
      creator = DiscussionComment::Creator.new(
        discussion: @discussion,
        actor: @user,
        body: body,
      )
      assert creator.save
      assert_empty creator.errors
      assert_predicate @discussion, :open?
      assert_predicate creator.comment, :persisted?
      assert_equal @discussion, creator.comment.discussion
      assert_nil creator.comment.parent_comment
      assert_equal @user, creator.comment.user
      assert_equal body, creator.comment.body
    end

    test "creates a new nested comment" do
      body = "stream cellophane by fka twigs"
      creator = DiscussionComment::Creator.new(
        discussion: @discussion,
        actor: @user,
        body: body,
        parent_comment_id: @comment.id,
      )
      assert creator.save
      assert_empty creator.errors
      assert_predicate @discussion, :open?
      assert_predicate creator.comment, :persisted?
      assert_equal @discussion, creator.comment.discussion
      assert_equal @comment, creator.comment.parent_comment
      assert_equal @user, creator.comment.user
      assert_equal body, creator.comment.body
    end

    test "requires a body for regular comment" do
      creator = DiscussionComment::Creator.new(
        discussion: @discussion,
        actor: @user,
        body: "",
      )
      refute creator.save
      assert_equal ["Body can't be blank"], creator.errors.full_messages
      assert_predicate @discussion, :open?
      refute_predicate creator.comment, :persisted?
    end

    test "allows empty body if state is being changed" do
      state_reason = Discussion::StateReasonable::StateReason::Resolved.serialize
      creator = DiscussionComment::Creator.new(
        discussion: @discussion,
        actor: @user,
        body: "",
        state_reason: state_reason,
      )
      assert creator.save
      assert_predicate @discussion, :closed?
      assert_equal state_reason, @discussion.state_reason
      refute_predicate creator.comment, :persisted?
    end

    test "allows creating comment when state is being changed" do
      body = "hello everyone"
      state_reason = Discussion::StateReasonable::StateReason::Resolved.serialize
      creator = DiscussionComment::Creator.new(
        discussion: @discussion,
        actor: @user,
        body: body,
        state_reason: state_reason,
      )
      assert creator.save
      assert_empty creator.errors
      assert_predicate @discussion, :closed?
      assert_equal state_reason, @discussion.state_reason
      assert_predicate creator.comment, :persisted?
      assert_equal @discussion, creator.comment.discussion
      assert_nil creator.comment.parent_comment
      assert_equal @user, creator.comment.user
      assert_equal body, creator.comment.body
    end

    test "returns error if invalid state reason for close is specified" do
      creator = DiscussionComment::Creator.new(
        discussion: @discussion,
        actor: @user,
        body: "",
        state_reason: "dahyun",
      )
      refute creator.save
      assert_equal ["State reason must be a valid reason"], creator.errors.full_messages
      assert_predicate @discussion, :open?
      refute_predicate creator.comment, :persisted?
    end

    test "returns error if user is not authorized to close discussion" do
      rando = create(:verified_user)
      creator = DiscussionComment::Creator.new(
        discussion: @discussion,
        actor: rando,
        body: "hello everyone",
        state_reason: Discussion::StateReasonable::StateReason::Resolved.serialize,
      )
      refute creator.save
      assert_equal ["Discussion state could not be updated"], creator.errors.full_messages
      assert_predicate @discussion, :open?
      refute_predicate creator.comment, :persisted?
    end
  end
end
