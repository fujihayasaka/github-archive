# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestReviewCreatorTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, plan: "micro")
    @forker = create(:user, login: "forker")

    @source = create(:private_repository, owner: @owner, from_example: :review_comment_source)
    @source.add_member @forker, action: :write

    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :review_comment_fork)

    @issue = create(:issue, user: @forker, repository: @source)

    @pull = PullRequest.create_for!(@source,
      base: "master",
      head: "#{@fork.user}:topic",
      user: @issue.user,
      issue: @issue)
    @issue.pull_request = @pull

    review = @pull.reviews.create!(
      user: @owner,
      head_sha: @pull.head_sha,
    )

    @comment = create(:pull_request_review_comment,
      pull_request: @pull,
      user: @owner,
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 21,
      body: "ship it",
      pull_request_review_id: review.id,
    )

    review.comment!
  end

  def full_comparison(pull)
    PullRequest::Comparison.find(pull: pull, start_commit_oid: pull.merge_base,
      end_commit_oid: pull.head_sha, base_commit_oid: pull.merge_base)
  end

  test "creates a comment at a path and position" do
    result = PullRequestReview::Creator.execute(pull_request: @pull,
      user: @forker,
      body: "review body!",
      comments: [
        { body: "comment body",
          path: "aquaman.txt",
          position: 21,
        },
      ],
    )
    assert_predicate result, :success?
    assert_predicate result.review, :valid?
    assert_equal 1, result.review.review_comments.count
  end

  test "creates a comment with path, line, and side" do
    result = PullRequestReview::Creator.execute(pull_request: @pull,
      user: @forker,
      body: "review body!",
      comments: [
        { body: "comment body",
          path: "aquaman.txt",
          line: 18,
          side: "right",
        },
      ],
    )
    assert_predicate result, :success?
    assert_predicate result.review, :valid?
    assert_equal 1, result.review.review_comments.count
  end

  test "creates a multi-line comment" do
    result = PullRequestReview::Creator.execute(pull_request: @pull,
      user: @forker,
      body: "review body!",
      comments: [
        { body: "comment body",
          path: "aquaman.txt",
          start_line: 26,
          start_side: "left",
          line: 28,
          side: "right",
        },
      ],
    )
    assert_predicate result, :success?
    assert_predicate result.review, :valid?
    assert_equal 1, result.review.review_comments.count
  end

  test "can create a review at a specific SHA" do
    comparison = PullRequest::Comparison.find(
      pull: @pull,
      start_commit_oid: @pull.merge_base,
      end_commit_oid: "54bb654c9e6025347f57900a4a5c2313a96b8035",
      base_commit_oid: @pull.merge_base,
    )

    result = PullRequestReview::Creator.execute(pull_request: @pull,
      user: @forker,
      body: "review body!",
      comments: [
        { body: "comment body",
          path: "aquaman.txt",
          position: 21,
        },
      ],
      pull_comparison: comparison,
    )
    assert_predicate result, :success?
    assert_predicate result.review, :valid?
    assert_equal "54bb654c9e6025347f57900a4a5c2313a96b8035", result.review.head_sha
  end

  test "creates a reply comment" do
    result = PullRequestReview::Creator.execute(pull_request: @pull,
      user: @forker,
      body: "review body!",
      comments: [
        { body: "comment body",
          in_reply_to: @comment.id,
        },
      ],
    )
    assert_predicate result, :success?
    assert_predicate result.review, :valid?
    reply = result.review.review_comments.reload.first
    assert_equal @comment.id, reply.reply_to_id
    assert_predicate reply, :reply?
  end

  test "skips callbacks on review comments and executes async callback job" do
    GitHub.flipper[:async_pr_review_comment_callbacks].enable
    PullRequestReviewComment.any_instance.expects(:after_commit_on_create_callbacks).never

    assert_enqueued_with(job: ReviewCommentBulkCreationCallbacksJob) do
      result = PullRequestReview::Creator.execute(pull_request: @pull,
        user: @forker,
        body: "review body!",
        comments: [
          { body: "comment body",
            path: "aquaman.txt",
            position: 21,
          },
        ],
      )
      assert_predicate result, :success?
      assert_predicate result.review, :valid?
      assert_equal 1, result.review.review_comments.count
    end
  end

  test "Actions can't create a pr approval if business has setting to prevent github actions approval" do
    setup_business_actions_state(can_approve_pr: false)

    result = PullRequestReview::Creator.execute(
      pull_request: @pull,
      user: @installation.bot,
      event: "approve"
    )
    refute_predicate result, :success?
    assert_equal result.errors, ["GitHub Actions is not permitted to approve pull requests."]
  end

  test "Actions can create a pr change request if business has setting to prevent github actions approval" do
    setup_business_actions_state(can_approve_pr: false)

    result = PullRequestReview::Creator.execute(
      pull_request: @pull,
      user: @installation.bot,
      event: "request_changes",
      body: "Nice try body"
    )
    assert_predicate result, :success?
    assert_predicate result.review, :valid?
  end

  test "Actions can create a pr approval if business has setting to allow github actions approval" do
    setup_business_actions_state(can_approve_pr: true)

    result = PullRequestReview::Creator.execute(
      pull_request: @pull,
      user: @installation.bot,
      event: "approve"
    )
    assert_predicate result, :success?
    assert_predicate result.review, :valid?
  end

  test "rejects a review if org has setting to prevent github actions approval" do
    setup_org_actions_state(can_approve_pr: false)

    result = PullRequestReview::Creator.execute(
      pull_request: @pull,
      user: @installation.bot,
      event: "approve"
    )
    refute_predicate result, :success?
    assert_equal result.errors, ["GitHub Actions is not permitted to approve pull requests."]
  end

  test "can create a review if org has setting to allow github actions approval" do
    setup_org_actions_state(can_approve_pr: true)

    result = PullRequestReview::Creator.execute(
      pull_request: @pull,
      user: @installation.bot,
      event: "approve"
    )
    assert_predicate result, :success?
    assert_predicate result.review, :valid?
  end

  test "can create a review comment if org has setting to prevent github actions approval" do
    setup_org_actions_state(can_approve_pr: false)

    result = PullRequestReview::Creator.execute(
      pull_request: @pull,
      user: @installation.bot,
      event: "comment",
      body: "Test",
      comments: [
        {
          body: "comment body",
          in_reply_to: @comment.id
        }
      ]
    )
    assert_predicate result, :success?
    assert_predicate result.review, :valid?
  end

  test "rejects a review if repo has setting to prevent github actions approval" do
    setup_repo_actions_state(can_approve_pr: false)

    result = PullRequestReview::Creator.execute(
      pull_request: @pull,
      user: @installation.bot,
      event: "approve"
    )
    refute_predicate result, :success?
    assert_equal result.errors, ["GitHub Actions is not permitted to approve pull requests."]
  end

  test "can create a review if repo has setting to allow github actions approval" do
    setup_repo_actions_state(can_approve_pr: true)

    result = PullRequestReview::Creator.execute(
      pull_request: @pull,
      user: @installation.bot,
      event: "approve"
    )
    assert_predicate result, :success?
    assert_predicate result.review, :valid?
  end

  test "can create a review comment if repo has setting to prevent github actions approval" do
    setup_repo_actions_state(can_approve_pr: false)

    result = PullRequestReview::Creator.execute(
      pull_request: @pull,
      user: @installation.bot,
      event: "comment",
      body: "Test",
      comments: [
        {
          body: "comment body",
          in_reply_to: @comment.id
        }
      ]
    )
    assert_predicate result, :success?
    assert_predicate result.review, :valid?
  end

  def setup_business_actions_state(can_approve_pr:)
    @business = create :business, owners: [@owner]
    @org = create :organization
    @org.set_actions_workflow_permission_can_approve_pr(true, @owner)
    @source.set_actions_workflow_permission_can_approve_pr(true, @owner)
    @business.add_organization @org

    @source.update_attribute(:owner, @org) # TODO: Is there a better way to do this?

    @business.set_actions_workflow_permission_can_approve_pr(can_approve_pr, @owner)
    @business.reload

    GitHub.stubs(:actions_enabled?).returns(true)

    make_trusted_oauth_apps_owner
    @actions_app = create :launch_integration
    @installation = make_integration_installation integration: @actions_app, target: @owner, permissions: {
      "actions" => :write,
      "pull_requests" => :write
    }
    @installation.bot.integration.stubs(:launch_github_app?).returns(true)
  end

  def setup_org_actions_state(can_approve_pr:)
    @business = create :business, owners: [@owner]
    @org = create :organization
    @business.add_organization @org
    @business.set_actions_workflow_permission_can_approve_pr(true, @owner)
    @source.set_actions_workflow_permission_can_approve_pr(true, @owner)

    @source.update_attribute(:owner, @org) # TODO: Is there a better way to do this?

    @org.set_actions_workflow_permission_can_approve_pr(can_approve_pr, @owner)
    @org.reload

    GitHub.stubs(:actions_enabled?).returns(true)

    make_trusted_oauth_apps_owner
    @actions_app = create :launch_integration
    @installation = make_integration_installation integration: @actions_app, target: @owner, permissions: {
      "actions" => :write,
      "pull_requests" => :write
    }
    @installation.bot.integration.stubs(:launch_github_app?).returns(true)
  end

  def setup_repo_actions_state(can_approve_pr:)
    @source.set_actions_workflow_permission_can_approve_pr(can_approve_pr, @owner)
    @source.reload

    GitHub.stubs(:actions_enabled?).returns(true)

    make_trusted_oauth_apps_owner
    @actions_app = create :launch_integration
    @installation = make_integration_installation integration: @actions_app, target: @owner, permissions: {
      "actions" => :write,
      "pull_requests" => :write
    }
    @installation.bot.integration.stubs(:launch_github_app?).returns(true)
  end
end
