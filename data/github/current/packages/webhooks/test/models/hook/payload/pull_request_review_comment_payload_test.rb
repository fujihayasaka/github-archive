# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadPullRequestReviewCommentPayloadTest < GitHub::TestCase
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
    @pr_review_comment = create :pull_request_review_comment, pull_request: @pull, user: @user
  end

  def build_pull_request_review_comment_payload(attrs = {})
    default_attrs = {
      action: :created,
      pull_request_review_comment_id: @pr_review_comment.id,
    }

    event = Hook::Event::PullRequestReviewCommentEvent.new(attrs.reverse_merge(default_attrs))
    Hook::Payload::PullRequestReviewCommentPayload.new event
  end

  context "when a pull request review comment is created" do
    test "v3" do
      payload = build_pull_request_review_comment_payload
      v3 = payload.to_hash

      assert_equal :created, v3[:action]
      assert_equal @pr_review_comment.id, v3[:comment][:id]
      assert_equal @pull.id, v3[:pull_request][:id]
      assert_equal @repo.id, v3[:repository][:id]
      assert_equal @repo.name, v3[:repository][:name]
      assert_equal @user.id, v3[:sender][:id]
      assert_equal @user.login, v3[:sender][:login]
      assert_merge_options_exist(@repo, @repo, v3)
    end

    test "payload does not include event changes" do
      payload = build_pull_request_review_comment_payload.to_hash
      refute_includes payload, :changes
    end
  end

  context "when a pull request review comment is updated" do
    test "v3" do
      payload = build_pull_request_review_comment_payload(action: :edited)
      v3 = payload.to_hash

      assert_equal :edited, v3[:action]
      assert_equal @pr_review_comment.id, v3[:comment][:id]
      assert_equal @pull.id, v3[:pull_request][:id]
      assert_equal @repo.id, v3[:repository][:id]
      assert_equal @repo.name, v3[:repository][:name]
      assert_equal @user.id, v3[:sender][:id]
      assert_equal @user.login, v3[:sender][:login]
      assert_merge_options_exist(@repo, @repo, v3)
    end

    test "includes changes in payload when present in event" do
      changes = { old_body: "Original", body: "Updated" }
      event = Hook::Event::PullRequestReviewCommentEvent.new(
        action: :edited,
        changes: changes,
        pull_request_review_comment_id: @pr_review_comment.id,
      )

      event.stub :changes, changes do
        payload = Hook::Payload::PullRequestReviewCommentPayload.new(event).to_hash
        assert_includes payload, :changes
      end
    end

    test "does not include changes in payload when not included in event" do
      payload = build_pull_request_review_comment_payload(action: :edited).to_hash
      refute_includes payload, :changes
    end
  end

  context "when a pull request review comment is deleted" do
    test "v3" do
      payload = build_pull_request_review_comment_payload(action: :deleted)
      v3 = payload.to_hash

      assert_equal :deleted, v3[:action]
      assert_equal @pr_review_comment.id, v3[:comment][:id]
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
