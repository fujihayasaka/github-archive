# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadPullRequestReviewPayloadTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @user = create(:user)
    @repo = create :repository, owner: @user, from_example: :rebase_pull_request
    @issue = create(:issue, user: @repo.owner, repository: @repo)
    @pull = create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "contrib",
      issue: @issue,
    )
    @pr_review = create :pull_request_review, pull_request: @pull, user: @user
    @pr_review.comment!
  end

  def build_pull_request_review_payload(action)
    default_attrs = {
      action: action,
      pull_request_review_id: @pr_review.id,
    }

    event = Hook::Event::PullRequestReviewEvent.new(default_attrs)
    Hook::Payload::PullRequestReviewPayload.new event
  end

  context "when a pull request review is submitted" do
    test "v3" do
      payload = build_pull_request_review_payload(:submitted)
      v3 = payload.to_hash
      assert_equal :submitted, v3[:action]
      assert_equal @pr_review.id, v3[:review][:id]
      assert_equal PullRequestReview.state_name(@pr_review.state), v3[:review][:state]
      assert_equal @pull.id, v3[:pull_request][:id]
      assert_equal @repo.id, v3[:repository][:id]
      assert_equal @repo.name, v3[:repository][:name]
      assert_equal @user.id, v3[:sender][:id]
      assert_equal @user.login, v3[:sender][:login]
      assert_merge_options_exist(@repo, @repo, v3)
    end
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::PullRequestReviewEvent,
      :action, :pull_request_review_id
  end

  context "changes" do
    test "returns a hash representation of the changed comment" do
      event = Hook::Event::PullRequestReviewEvent.new(
        action: :edited,
        pull_request_review_id: @pr_review.id,
        changes: { old_body: "Original Body", body: "Updated Body" },
      )

      assert_equal "Original Body", event.changes.fetch(:body).fetch(:from)
    end

    test "returns nil unless the changes are present in the event attributes" do
      event = Hook::Event::PullRequestReviewCommentEvent.new(
        action: :edited,
        pull_request_review_comment_id: @pr_review.id,
      )

      assert_nil event.changes
    end
  end

  context "when a pull request review is dismissed" do
    test "v3" do
      payload = build_pull_request_review_payload(:dismissed)
      v3 = payload.to_hash
      assert_equal :dismissed, v3[:action]
      assert_equal @pr_review.id, v3[:review][:id]
      assert_equal PullRequestReview.state_name(@pr_review.state), v3[:review][:state]
      assert_equal @pull.id, v3[:pull_request][:id]
      assert_equal @repo.id, v3[:repository][:id]
      assert_equal @repo.name, v3[:repository][:name]
      assert_equal @user.id, v3[:sender][:id]
      assert_equal @user.login, v3[:sender][:login]
      assert_merge_options_exist(@repo, @repo, v3)
    end
  end

  def assert_merge_options_exist(head_repo, base_repo, v3)
    head_repo_hash = v3[:pull_request][:head][:repo]
    assert_equal head_repo.squash_merge_allowed?, head_repo_hash[:allow_squash_merge]
    assert_equal head_repo.merge_commit_allowed?, head_repo_hash[:allow_merge_commit]
    assert_equal head_repo.rebase_merge_allowed?, head_repo_hash[:allow_rebase_merge]
    assert_equal head_repo.delete_branch_on_merge?, head_repo_hash[:delete_branch_on_merge]

    base_repo_hash = v3[:pull_request][:base][:repo]
    assert_equal base_repo.squash_merge_allowed?, base_repo_hash[:allow_squash_merge]
    assert_equal base_repo.merge_commit_allowed?, base_repo_hash[:allow_merge_commit]
    assert_equal base_repo.rebase_merge_allowed?, base_repo_hash[:allow_rebase_merge]
    assert_equal base_repo.delete_branch_on_merge?, base_repo_hash[:delete_branch_on_merge]
  end
end
