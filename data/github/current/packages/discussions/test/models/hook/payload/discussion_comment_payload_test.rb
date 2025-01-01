# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadDiscussionCommentPayloadTest < GitHub::TestCase
  fixtures do
    @user = create(:verified_user)
    @comment = create(:discussion_comment, user: @user)
  end

  context "when the discussion comment is created" do
    test "v3" do
      payload = build_comment_payload(action: :created)
      v3 = payload.to_hash

      assert_equal :created, v3[:action]
      assert_equal @comment.id, v3[:comment][:id]
      assert_equal @comment.body, v3[:comment][:body]
      assert_equal @comment.discussion.id, v3[:discussion][:id]
      assert_equal @comment.repository.id, v3[:repository][:id]
      assert_equal @user.id, v3[:sender][:id]
      assert_equal @user.login, v3[:sender][:login]
    end
  end

  context "when the discussion comment's body is updated" do
    test "v3" do
      changes = { old_body: "old and busted", body: "new hotness" }
      payload = build_comment_payload(action: :edited, changes: changes)
      v3 = payload.to_hash

      assert_equal :edited, v3[:action]
      assert_equal @comment.id, v3[:comment][:id]
      assert_equal @comment.discussion.id, v3[:discussion][:id]
      assert_equal @comment.repository.id, v3[:repository][:id]
      assert_equal @user.id, v3[:sender][:id]
      assert_equal "old and busted", v3[:changes][:body][:from]
    end
  end

  def build_comment_payload(attrs = {})
    default_attrs = {
      action: :created,
      comment_id: @comment.id,
      actor_id: @user.id,
    }

    event = Hook::Event::DiscussionCommentEvent.new(attrs.reverse_merge(default_attrs))
    Hook::Payload::DiscussionCommentPayload.new(event)
  end
end
