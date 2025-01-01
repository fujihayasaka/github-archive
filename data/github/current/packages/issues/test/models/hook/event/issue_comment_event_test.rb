# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventIssueCommentEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @org            = create(:organization)
    @repo           = create :repository, owner: @org
    @issue          = create :issue, repository: @repo, user: @org
    @issue_comment  = create :issue_comment, issue: @issue
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::IssueCommentEvent, :action, :issue_comment_id
  end

  context "#issue_comment" do
    test "returns the specified issue comment" do
      event = Hook::Event::IssueCommentEvent.new action: :created, issue_comment_id: @issue_comment.id
      assert_equal @issue_comment, event.issue_comment
    end
  end

  context "#target_repository" do
    test "returns the repository of the specified issue comment" do
      event = Hook::Event::IssueCommentEvent.new action: :created, issue_comment_id: @issue_comment.id
      assert_equal @issue_comment.repository, event.target_repository
    end
  end

  context "#actor" do
    test "returns the modifying_user of the specified issue comment" do
      event = Hook::Event::IssueCommentEvent.new action: :created, issue_comment_id: @issue_comment.id
      assert_equal @issue_comment.user, event.actor
    end
  end

  context "#deliverable?" do
    test "returns false if the IssueComment is not found" do
      event = Hook::Event::IssueCommentEvent.new action: :created, issue_comment_id: -1
      refute_predicate event, :deliverable?
    end

    test "returns true for if a target_repository and comment are present" do
      event = Hook::Event::IssueCommentEvent.new action: :created, issue_comment_id: @issue_comment.id
      assert_predicate event, :deliverable?
    end
  end

  context "#changes" do
    test "includes the original version of the body when they're passed to the event" do
      event = Hook::Event::IssueCommentEvent.new(
        action: :edited,
        issue_comment_id: @issue_comment.id,
        old_body: "Original Body",
      )

      assert_equal event.changes[:body][:from], "Original Body"
    end

    test "does not include the original version if they're not passed to the event" do
      event = Hook::Event::IssueCommentEvent.new(
        action: :edited,
        issue_comment_id: @issue_comment.id,
        old_body: nil,
      )

      assert_nil event.changes
    end
  end

  context "#deliver" do
    test "handles deleted comment" do
      event = Hook::Event::IssueCommentEvent.new action: :created, issue_comment_id: @issue_comment.id
      @issue_comment.destroy

      assert_nil event.target_repository
      event.deliver
    end
  end

  context "#model_importing?" do
    test "returns true when the repo locked for migration" do
      @repo.lock_for_migration
      event = Hook::Event::IssueCommentEvent.new action: :created, issue_comment_id: @issue_comment.id
      assert event.model_importing?
      assert_predicate event, :model_importing?
    end

    test "returns false when the repo is not locked for migration" do
      event = Hook::Event::IssueCommentEvent.new action: :created, issue_comment_id: @issue_comment.id
      refute event.model_importing?
      refute_predicate event, :model_importing?
    end
  end
end
