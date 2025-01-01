# typed: true
# frozen_string_literal: true

require "test_helper"

class FeedPostReferenceTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user)
  end

  context ".from_post" do
    test "Returns user mention references" do
      post = create(:feed_post, body: "Check out @#{@user.login}")
      references = FeedPostReference.from_post(post)

      assert_equal 1, references.count

      reference = references.first
      assert_equal "User", reference.reference_type
      assert_equal @user.id, reference.reference_id
      assert_equal "mention", reference.action
    end

    test "Returns issue references" do
      repo = create(:public_repository, owner: @user)
      issue = create(:issue, repository: repo, user: @user)
      issue_url = "#{GitHub.url}/#{repo.nwo}/issues/#{issue.number}"

      post = create(:feed_post, body: "This issue #{issue_url}")
      references = FeedPostReference.from_post(post)

      assert_equal 1, references.count

      reference = references.first
      assert_equal "Issue", reference.reference_type
      assert_equal issue.id, reference.reference_id
      assert_equal "mention", reference.action
    end

    test "Returns pull request references" do
      repo = create(:repository, owner: @user, from_example: :pull_request_source)
      pr_branch = "master-merged-topic"
      pr = create(:pull_request, user: @user, repository: repo, base_repository: repo, head_repository: repo, head_ref: pr_branch)
      pr_url = "#{GitHub.url}/#{repo.nwo}/pull/#{pr.number}"

      post = create(:feed_post, body: "This pr #{pr_url} is good")
      references = FeedPostReference.from_post(post)

      assert_equal 1, references.count

      reference = references.first
      assert_equal "PullRequest", reference.reference_type
      assert_equal pr.id, reference.reference_id
      assert_equal "mention", reference.action
    end

    test "Returns repository references" do
      repo = create(:repository, owner: @user)
      repo_url = "#{GitHub.url}/#{repo.nwo}"
      post = create(:feed_post, body: "This repo #{repo_url} is great")
      references = FeedPostReference.from_post(post)

      assert_equal 1, references.count

      reference = references.first
      assert_equal "Repository", reference.reference_type
      assert_equal repo.id, reference.reference_id
      assert_equal "mention", reference.action
    end

    test "Returns discussion references" do
      repo = create(:repository, has_discussions: true)
      discussion = create(:discussion, repository: repo)
      discussion_url = "#{GitHub.url}/#{repo.nwo}/discussions/#{discussion.number}"
      post = create(:feed_post, body: "This #{discussion_url} is great")
      references = FeedPostReference.from_post(post)

      assert_equal 1, references.count

      reference = references.first
      assert_equal "Discussion", reference.reference_type
      assert_equal discussion.id, reference.reference_id
      assert_equal "mention", reference.action
    end
  end

  context "#action" do
    test "'mention' for user mention" do
      post = create(:feed_post, body: "Check out @#{@user.login}")
      references = FeedPostReference.from_post(post)

      assert_equal 1, references.count

      reference = references.first
      assert_equal "mention", reference.action
    end
  end
end
