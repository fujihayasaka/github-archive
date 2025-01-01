# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventPullRequestReviewCommentEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @org = create(:organization)
    user = create(:user)
    @repo = create :repository, owner: @org, from_example: :rebase_pull_request
    @repo.add_member user
    @issue = create(:issue, user: user, repository: @repo)
    @pull = create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "contrib",
      issue: @issue,
      user: @issue.user,
    )
    @pr_review_comment = create :pull_request_review_comment, pull_request: @pull
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::PullRequestReviewCommentEvent,
      :action, :pull_request_review_comment_id
  end

  context "#changes" do
    test "returns a hash representation of the changed comment" do
      event = Hook::Event::PullRequestReviewCommentEvent.new(
        action: :edited,
        pull_request_review_comment_id: @pr_review_comment.id,
        changes: { old_body: "Original Body", body: "Updated Body" },
      )

      assert_equal "Original Body", event.changes.fetch(:body).fetch(:from)
    end

    test "returns nil unless the changes are present in the event attributes" do
      event = Hook::Event::PullRequestReviewCommentEvent.new(
        action: :edited,
        pull_request_review_comment_id: @pr_review_comment.id,
      )

      assert_nil event.changes
    end
  end

  context "#pull_request_review_comment" do
    test "returns the specified comment" do
      event = Hook::Event::PullRequestReviewCommentEvent.new action: :created, pull_request_review_comment_id: @pr_review_comment.id
      assert_equal @pr_review_comment, event.pull_request_review_comment
    end
  end

  context "#target_repository" do
    test "returns the repo of the specified comment" do
      event = Hook::Event::PullRequestReviewCommentEvent.new action: :created, pull_request_review_comment_id: @pr_review_comment.id
      assert_equal @repo, event.target_repository
    end
  end

  context "#actor" do
    test "returns the author of the specified comment" do
      event = Hook::Event::PullRequestReviewCommentEvent.new action: :created, pull_request_review_comment_id: @pr_review_comment.id
      assert_equal @pr_review_comment.user, event.actor
    end
  end

  context "#deliverable?" do
    test "returns false if the comment is not found" do
      event = Hook::Event::PullRequestReviewCommentEvent.new action: :created, pull_request_review_comment_id: -1
      refute event.deliverable?
      refute_predicate event, :deliverable?
    end

    test "returns false if the comment is no longer associated with a PR" do
      @pull.delete
      event = Hook::Event::PullRequestReviewCommentEvent.new \
        action: :created,
        pull_request_review_comment_id: @pr_review_comment.id

      assert_nil @pr_review_comment.reload.pull_request
      refute_predicate event, :deliverable?
    end

    test "returns true when a target_repository and comment are present" do
      event = Hook::Event::PullRequestReviewCommentEvent.new action: :created, pull_request_review_comment_id: @pr_review_comment.id
      assert event.deliverable?
      assert_predicate event, :deliverable?
    end
  end

  context "#model_importing?" do
    test "returns true when the repo locked for migration" do
      @repo.lock_for_migration
      event = Hook::Event::PullRequestReviewCommentEvent.new action: :created, pull_request_review_comment_id: @pr_review_comment.id
      assert event.model_importing?
      assert_predicate event, :model_importing?
    end

    test "returns false when the repo is not locked for migration" do
      event = Hook::Event::PullRequestReviewCommentEvent.new action: :created, pull_request_review_comment_id: @pr_review_comment.id
      refute event.model_importing?
      refute_predicate event, :model_importing?
    end
  end

  context "#deliver" do
    test "handles deleted comment" do
      event = Hook::Event::PullRequestReviewCommentEvent.new action: :edited, pull_request_review_comment_id: @pr_review_comment.id
      @pr_review_comment.destroy

      assert_nil event.target_repository
      event.deliver
    end
  end
end
