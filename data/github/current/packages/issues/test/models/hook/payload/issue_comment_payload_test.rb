# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadIssueCommentPayloadTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository)
    @issue = create :issue, user: @user, repository: @repo
    @issue_comment = create :issue_comment, issue: @issue
  end

  context "when an issue comment is created" do
    test "v3" do
      payload = build_issue_comment_payload
      v3 = payload.to_hash

      assert_equal :created, v3[:action]
      assert_equal @issue.id, v3[:issue][:id]
      assert_equal @issue_comment.id, v3[:comment][:id]
      assert_equal @repo.id, v3[:repository][:id]
      assert_equal @user.id, v3[:sender][:id]
    end

    test "payload does not include event changes" do
      payload = build_issue_comment_payload.to_hash
      refute_includes payload, :changes
    end
  end

  context "when an issue comment is updated" do
    test "v3" do
      payload = build_issue_comment_payload(action: :edited)
      v3 = payload.to_hash

      assert_equal :edited, v3.fetch(:action)
      assert_equal @issue.id, v3.fetch(:issue).fetch(:id)
      assert_equal @issue_comment.id, v3.fetch(:comment).fetch(:id)
      assert_equal @repo.id, v3.fetch(:repository).fetch(:id)
      assert_equal @user.id, v3.fetch(:sender).fetch(:id)
    end

    test "includes changes in payload when present in event" do
      event = Hook::Event::IssueCommentEvent.new(
        action: :edited,
        issue_comment_id: @issue_comment.id,
        old_body: "Original",
      )

      payload = Hook::Payload::IssueCommentPayload.new(event).to_hash
      assert_includes payload, :changes
    end

    test "does not include changes in payload when not included in event" do
      payload = build_issue_comment_payload(action: :edited).to_hash
      refute_includes payload, :changes
    end
  end

  def build_issue_comment_payload(attrs = {})
    default_attrs = {
      action: :created,
      issue_comment_id: @issue_comment.id,
    }

    event = Hook::Event::IssueCommentEvent.new(attrs.reverse_merge(default_attrs))
    Hook::Payload::IssueCommentPayload.new(event)
  end

end
