# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadCommitCommentPayloadTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create :repository, owner: @user
    @commit_comment = create :commit_comment, repository: @repo, user: @user
  end

  context "Creating a commit comment" do
    test "v3" do
      payload = build_commit_comment_payload
      v3 = payload.to_hash

      assert_equal :created, v3[:action]
      assert_equal @commit_comment.id, v3[:comment][:id]
      assert_equal @commit_comment.position, v3[:comment][:position]
      assert_equal @repo.id, v3[:repository][:id]
      assert_equal @user.id, v3[:sender][:id]
    end
  end

  def build_commit_comment_payload(attrs = {})
    default_attrs = {
      action: :created,
      commit_comment_id: @commit_comment.id,
    }

    event = Hook::Event::CommitCommentEvent.new(attrs.reverse_merge(default_attrs))
    Hook::Payload::CommitCommentPayload.new(event)
  end
end
