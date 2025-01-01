# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequests::Copilot::CodeReviewGeneratorTest < GitHub::TestCase
  fixtures do
    @owner = create(:paid_user)
    @org = create(:organization, admin: @owner)
    @repo  = create(:private_repository, owner: @org, from_example: :with_tokens)

    example_repo :pull_request_source, @repo
    @pull = PullRequest.create_for! @repo, user: @owner, base: "master", head: "master-forward-2", title: "asdf", body: "asdf"

    @github_org = create(:organization, login: "github", admin: @owner)
    @github_repo = create(:private_repository, owner: @github_org, from_example: :with_tokens)
    example_repo :pull_request_source, @github_repo
    @github_pull = PullRequest.create_for! @github_repo, user: @owner, base: "master", head: "master-forward-2", title: "asdf", body: "asdf"

    make_trusted_oauth_apps_owner
    integration = Apps::Internal::CopilotPullRequestReviewer.seed_database!
    InternalAppHelper.reconfigure_internal_app(app_alias: :copilot_pull_request_reviewer, app: integration)
    @bot = ::Apps::Internal.integration(:copilot_pull_request_reviewer).bot
  end

  test "send request to CAPI", skip_enterprise: true do
    Failbot.expects(:report).never

    comment = {
      path: "pkg/codereviewagent/pullrequestreview.go",
      line: 17,
      body: "The word 'reprsents' should be corrected to 'represents'.\n```suggestion\n    // PullRequestReview represents a review that contains comments from Copilot.\n```",
      side: "RIGHT",
    }

    response = {
      choices: nil,
      copilot_references: [
        {
          type: "github.generated-pull-request-comment",
          data: comment,
          id: "",
          metadata: { display_name: "", display_icon: "" }
        }
      ]
    }

    fake_capi_user = mock("capi user", create_code_review: response)
    Copilot::User::CopilotApi.expects(:new).once.returns(fake_capi_user)

    fake_review_creator = mock("review creator")
    fake_review_creator.expects(:create).once
    PullRequests::Copilot::CodeReviewCreator.expects(:new).once.with(
      pull: @pull,
      repo: @repo,
      commit_id: @pull.head_sha,
      comments: [comment],
      diff_start_commit_oid: @pull.base_sha,
      diff_end_commit_oid: @pull.head_sha,
      diff_base_commit_oid: @pull.merge_base,
      body: nil,
    ).returns(fake_review_creator)

    generator = PullRequests::Copilot::CodeReviewGenerator.new(
      repo: @repo,
      pull: @pull,
      requestor: @owner,
    )
    generator.generate
  end

  test "create a code review with nil body for github-owned repo", skip_enterprise: true do
    GitHub.flipper[:copilot_code_reviews_internal_feedback_advert].disable
    Failbot.expects(:report).never

    comment = {
      path: "pkg/codereviewagent/pullrequestreview.go",
      line: 17,
      body: "The word 'reprsents' should be corrected to 'represents'.\n```suggestion\n    // PullRequestReview represents a review that contains comments from Copilot.\n```",
      side: "RIGHT",
    }

    response = {
      choices: nil,
      copilot_references: [
        {
          type: "github.generated-pull-request-comment",
          data: comment,
          id: "",
          metadata: { display_name: "", display_icon: "" }
        }
      ]
    }

    fake_capi_user = mock("capi user", create_code_review: response)
    Copilot::User::CopilotApi.expects(:new).once.returns(fake_capi_user)

    fake_review_creator = mock("review creator")
    fake_review_creator.expects(:create).once
    PullRequests::Copilot::CodeReviewCreator.expects(:new).once.with(
      pull: @github_pull,
      repo: @github_repo,
      commit_id: @github_pull.head_sha,
      comments: [comment],
      diff_start_commit_oid: @github_pull.base_sha,
      diff_end_commit_oid: @github_pull.head_sha,
      diff_base_commit_oid: @github_pull.merge_base,
      body: nil,
    ).returns(fake_review_creator)

    generator = PullRequests::Copilot::CodeReviewGenerator.new(
      repo: @github_repo,
      pull: @github_pull,
      requestor: @owner,
    )
    generator.generate
  end

  test "create a code review with feedback advert in body for github-owned repo when feature flag is enabled", skip_enterprise: true do
    GitHub.flipper[:copilot_code_reviews_internal_feedback_advert].enable
    Failbot.expects(:report).never

    comment = {
      path: "pkg/codereviewagent/pullrequestreview.go",
      line: 17,
      body: "The word 'reprsents' should be corrected to 'represents'.\n```suggestion\n    // PullRequestReview represents a review that contains comments from Copilot.\n```",
      side: "RIGHT",
    }

    response = {
      choices: nil,
      copilot_references: [
        {
          type: "github.generated-pull-request-comment",
          data: comment,
          id: "",
          metadata: { display_name: "", display_icon: "" }
        }
      ]
    }

    fake_capi_user = mock("capi user", create_code_review: response)
    Copilot::User::CopilotApi.expects(:new).once.returns(fake_capi_user)

    fake_review_creator = mock("review creator")
    fake_review_creator.expects(:create).once
    PullRequests::Copilot::CodeReviewCreator.expects(:new).once.with(
      pull: @github_pull,
      repo: @github_repo,
      commit_id: @github_pull.head_sha,
      comments: [comment],
      diff_start_commit_oid: @github_pull.base_sha,
      diff_end_commit_oid: @github_pull.head_sha,
      diff_base_commit_oid: @github_pull.merge_base,
      body: regexp_matches(/short 3 minute survey/),
    ).returns(fake_review_creator)

    generator = PullRequests::Copilot::CodeReviewGenerator.new(
      repo: @github_repo,
      pull: @github_pull,
      requestor: @owner,
    )
    generator.generate
  end

  test "create a code review with no body for github-owned repo when feature flag is enabled if there are no comments", skip_enterprise: true do
    GitHub.flipper[:copilot_code_reviews_internal_feedback_advert].enable
    Failbot.expects(:report).never

    response = {
      choices: nil,
      copilot_references: []
    }

    fake_capi_user = mock("capi user", create_code_review: response)
    Copilot::User::CopilotApi.expects(:new).once.returns(fake_capi_user)

    fake_review_creator = mock("review creator")
    fake_review_creator.expects(:create).once
    PullRequests::Copilot::CodeReviewCreator.expects(:new).once.with(
      pull: @github_pull,
      repo: @github_repo,
      commit_id: @github_pull.head_sha,
      comments: [],
      diff_start_commit_oid: @github_pull.base_sha,
      diff_end_commit_oid: @github_pull.head_sha,
      diff_base_commit_oid: @github_pull.merge_base,
      body: nil,
    ).returns(fake_review_creator)

    generator = PullRequests::Copilot::CodeReviewGenerator.new(
      repo: @github_repo,
      pull: @github_pull,
      requestor: @owner,
    )
    generator.generate
  end

  test "Destroy any existing review if process fails", skip_enterprise: true do
    Failbot.expects(:report).never

    comment = {
      path: "pkg/codereviewagent/pullrequestreview.go",
      line: 17,
      body: "The word 'reprsents' should be corrected to 'represents'.\n```suggestion\n    // PullRequestReview represents a review that contains comments from Copilot.\n```",
      side: "RIGHT",
    }

    assert_equal @pull.reviews.length, 0

    crc = PullRequests::Copilot::CodeReviewCreator.new(
      pull: @pull,
      repo: @repo,
      commit_id: @pull.head_sha,
      comments: [comment],
      diff_start_commit_oid: @pull.base_sha,
      diff_end_commit_oid: @pull.head_sha,
      diff_base_commit_oid: @pull.merge_base,
      body: nil,
    ).create

    assert_equal @pull.reviews.reload.length, 0
  end
end
