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
    integration = Apps::Privileged::CopilotPullRequestReviewer.seed_database!
    PrivilegedAppHelper.reconfigure_privileged_app(app_alias: :copilot_pull_request_reviewer, app: integration)
    @bot = ::Apps::Privileged.integration(:copilot_pull_request_reviewer).bot
    @summary = { overall_summary: "Overall summary", per_file_summary: "| File | Description |
| ---- | ----------- |
| file1 | description |
| file2 | description |
| fileN | description |" }
  end

  setup do
    PullRequests::Copilot::CodeReviewAccess.any_instance.stubs(:can_create_review_request?).returns(true)
    disable_feature_flag(:expand_supported_languages_cpp)
    disable_feature_flag(:copilot_code_review_enable_c_support)
  end

  test "sends request to CAPI and persists a PR review", skip_enterprise: true do
    Failbot.expects(:report).never
    @pull.stubs(:changed_files).returns(1)

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
          type: "github.pull-request-summary",
          data: @summary,
        },
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
    fake_review_creator.expects(:create).once.returns(true)
    PullRequests::Copilot::CodeReviewCreator.expects(:new).once.with(
      pull: @pull,
      repo: @repo,
      commit_id: @pull.head_sha,
      comments: [comment],
      diff_start_commit_oid: @pull.base_sha,
      diff_end_commit_oid: @pull.head_sha,
      diff_base_commit_oid: @pull.merge_base,
      body: regexp_matches(/#{Regexp.escape(@summary[:overall_summary])}.*?Copilot reviewed 1 out of 1 changed files in this pull request and generated 1 comment.*?#{Regexp.escape(@summary[:per_file_summary])}.*?/m),
      return_with_error: false,
    ).returns(fake_review_creator)

    generator = PullRequests::Copilot::CodeReviewGenerator.new(
      repo: @repo,
      pull: @pull,
      requestor: @owner,
    )
    assert generator.generate, "expected review persistence to succeed"
  end

  test "sends supported cpp experiment header when flag is turned on", skip_enterprise: true do
    enable_feature_flag(:expand_supported_languages_cpp, @repo.owner)
    serializer = Copilot::PullRequests::CodeReviewReferenceSerializer.new
    pr_ref = serializer.to_hash(@pull, include_diff: true, include_full_files: true)
    interaction_type = PullRequests::Copilot::CodeReviewGenerator::INTERACTION_TYPE_SLUG

    PullRequests::Copilot::CodeReviewGenerator.any_instance.stubs(:generate_interaction_id).returns("stubbed-out-interaction-id")
    Copilot::User::CopilotApi.any_instance.expects(:create_code_review).with(
      references: [pr_ref],
      role: "user",
      experiment_headers: { "X-Experiment-Expand-Supported-Languages-Cpp" => "true" },
      interaction_id: "stubbed-out-interaction-id",
      interaction_type: interaction_type
    ).returns({}.with_indifferent_access)

    # we don't care about submitting reviews for this test
    PullRequests::Copilot::CodeReviewGenerator.any_instance.stubs(:submit_review).returns(true)

    generator = PullRequests::Copilot::CodeReviewGenerator.new(
      repo: @repo,
      pull: @pull,
      requestor: @owner,
    )
    assert generator.generate
  end

  test "sends experiment header to enable C support when flag is turned on", skip_enterprise: true do
    enable_feature_flag(:copilot_code_review_enable_c_support, @repo.owner)
    serializer = Copilot::PullRequests::CodeReviewReferenceSerializer.new
    pr_ref = serializer.to_hash(@pull, include_diff: true, include_full_files: true)
    interaction_type = PullRequests::Copilot::CodeReviewGenerator::INTERACTION_TYPE_SLUG

    PullRequests::Copilot::CodeReviewGenerator.any_instance.stubs(:generate_interaction_id).returns("stubbed-out-interaction-id")
    Copilot::User::CopilotApi.any_instance.expects(:create_code_review).with(
      references: [pr_ref],
      role: "user",
      experiment_headers: { "X-Experiment-Expand-Supported-Languages-C" => "true" },
      interaction_id: "stubbed-out-interaction-id",
      interaction_type: interaction_type
    ).returns({}.with_indifferent_access)

    # we don't care about submitting reviews for this test
    PullRequests::Copilot::CodeReviewGenerator.any_instance.stubs(:submit_review).returns(true)

    generator = PullRequests::Copilot::CodeReviewGenerator.new(
      repo: @repo,
      pull: @pull,
      requestor: @owner,
    )
    assert generator.generate
  end

  test "emits a successful persistence metric if review creation is successful", skip_enterprise: true do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    # stub an empty but successful response from CAPI
    response = { choices: nil, copilot_references: [] }
    fake_capi_user = mock("capi user", create_code_review: response)
    Copilot::User::CopilotApi.expects(:new).once.returns(fake_capi_user)

    PullRequests::Copilot::CodeReviewCreator.any_instance.expects(:create).returns(true)

    generator = PullRequests::Copilot::CodeReviewGenerator.new(
      repo: @repo,
      pull: @pull,
      requestor: @owner,
    )
    assert generator.generate, "expected review persistence to succeed"

    metric = GitHub.dogstats.increments("copilot.code_review.persistence").first
    assert metric, "expected a persistence metric to be emitted"
    assert_includes metric.tags, "success:true"
  end

  test "emits a failed persistence metric if review creation fails", skip_enterprise: true do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    # stub an empty but successful response from CAPI
    response = { choices: nil, copilot_references: [] }
    fake_capi_user = mock("capi user", create_code_review: response)
    Copilot::User::CopilotApi.expects(:new).once.returns(fake_capi_user)

    PullRequests::Copilot::CodeReviewCreator.any_instance.expects(:create).returns(false)

    generator = PullRequests::Copilot::CodeReviewGenerator.new(
      repo: @repo,
      pull: @pull,
      requestor: @owner,
    )
    refute generator.generate, "expected review persistence to fail"

    metric = GitHub.dogstats.increments("copilot.code_review.persistence").first
    assert metric, "expected a persistence metric to be emitted"
    assert_includes metric.tags, "success:false"
  end

  test "Should raise if CopilotApi::UnauthorizedError occurs", skip_enterprise: true do
    message = PullRequests::Copilot::CodeReviewCreator::ERROR_COMMENTS

    enable_feature_flag(:copilot_pr_reviews_submit_error)

    Copilot::User::CopilotApi.any_instance.expects(:make_request).raises(CopilotAPI::UnauthorizedError)

    @github_pull.review_requests.create(reviewer: @bot)

    generator = PullRequests::Copilot::CodeReviewGenerator.new(
      repo: @github_repo,
      pull: @github_pull,
      requestor: @owner,
    )
    assert_raises(CopilotAPI::UnauthorizedError) { generator.generate }
  end

  test "Should return error comment if CopilotAPI::NotFoundError or CopilotAPI::NetworkError occurs", skip_enterprise: true do
    [CopilotAPI::NotFoundError, CopilotAPI::NetworkError].each do |error_class|
      message = PullRequests::Copilot::CodeReviewCreator::ERROR_COMMENTS

      @github_pull.review_requests.create(reviewer: @bot)

      Copilot::User::CopilotApi.any_instance.expects(:create_code_review).raises(error_class)

      generator = PullRequests::Copilot::CodeReviewGenerator.new(
        repo: @github_repo,
        pull: @github_pull,
        requestor: @owner,
      )
      assert generator.generate, "expected review persistence to succeed"

      assert_equal message, @github_pull.reviews.first.body
    end
  end

  test "Should return NO error comment if copilot has no comments", skip_enterprise: true do
    message = PullRequests::Copilot::CodeReviewCreator::ERROR_COMMENTS
    message_no_files = PullRequests::Copilot::ReviewBodyMessageGenerator::NO_FILES_BODY

    enable_feature_flag(:copilot_pr_reviews_submit_empty_reviews)

    @github_pull.review_requests.create(reviewer: @bot)

    response = { choices: nil, copilot_references: [] }

    fake_capi_user = mock("capi user", create_code_review: response)
    Copilot::User::CopilotApi.expects(:new).once.returns(fake_capi_user)

    generator = PullRequests::Copilot::CodeReviewGenerator.new(
      repo: @github_repo,
      pull: @github_pull,
      requestor: @owner,
    )
    assert generator.generate, "expected review persistence to succeed"

    refute_equal message, @github_pull.reviews.first.body
    assert_match /#{message_no_files}/, @github_pull.reviews.first.body
  end

  context "review_body_message" do
    test "returns a message that no files were reviewed and shows exclusions", skip_enterprise: true do
      Failbot.expects(:report).never
      @github_pull.stubs(:changed_files).returns(1)

      excluded_file = {
        file_path: "pkg/codereviewagent/pullrequestreview.rbi",
        language: "Ruby",
        reason: "file_type_not_supported",
      }

      response = {
        choices: nil,
        copilot_references: [
          {
            type: "github.excluded-file",
            data: excluded_file,
            id: "",
            metadata: { display_name: "", display_icon: "" }
          }
        ]
      }

      fake_capi_user = mock("capi user", create_code_review: response)
      Copilot::User::CopilotApi.expects(:new).once.returns(fake_capi_user)

      fake_review_creator = mock("review creator")
      fake_review_creator.expects(:create).once.returns(true)
      PullRequests::Copilot::CodeReviewCreator.expects(:new).once.with(
        pull: @github_pull,
        repo: @github_repo,
        commit_id: @github_pull.head_sha,
        comments: [],
        diff_start_commit_oid: @github_pull.base_sha,
        diff_end_commit_oid: @github_pull.head_sha,
        diff_base_commit_oid: @github_pull.merge_base,
        body: regexp_matches(/Copilot wasn't able to review any files in this pull request/),
        return_with_error: false,
      ).returns(fake_review_creator)

      generator = PullRequests::Copilot::CodeReviewGenerator.new(
        repo: @github_repo,
        pull: @github_pull,
        requestor: @owner,
      )
      generator.generate
    end

    test "returns a message that shows the number of reviewed files", skip_enterprise: true do
      Failbot.expects(:report).never
      @github_pull.stubs(:changed_files).returns(2)

      comment = {
        path: "pkg/codereviewagent/pullrequestreview.go",
        line: 17,
        body: "The word 'reprsents' should be corrected to 'represents'.\n```suggestion\n    // PullRequestReview represents a review that contains comments from Copilot.\n```",
        side: "RIGHT",
      }

      excluded_file = {
        file_path: "pkg/codereviewagent/pullrequestreview.rbi",
        language: "Ruby",
        reason: "file_type_not_supported",
      }

      response = {
        choices: nil,
        copilot_references: [
          {
            type: "github.generated-pull-request-comment",
            data: comment,
            id: "",
            metadata: { display_name: "", display_icon: "" }
          },
          {
            type: "github.excluded-file",
            data: excluded_file,
            id: "",
            metadata: { display_name: "", display_icon: "" }
          }
        ]
      }

      fake_capi_user = mock("capi user", create_code_review: response)
      Copilot::User::CopilotApi.expects(:new).once.returns(fake_capi_user)

      fake_review_creator = mock("review creator")
      fake_review_creator.expects(:create).once.returns(true)
      PullRequests::Copilot::CodeReviewCreator.expects(:new).once.with(
        pull: @github_pull,
        repo: @github_repo,
        commit_id: @github_pull.head_sha,
        comments: [comment],
        diff_start_commit_oid: @github_pull.base_sha,
        diff_end_commit_oid: @github_pull.head_sha,
        diff_base_commit_oid: @github_pull.merge_base,
        body: regexp_matches(/Copilot reviewed 1 out of 2 changed files in this pull request and generated 1 comment/),
        return_with_error: false,
      ).returns(fake_review_creator)

      generator = PullRequests::Copilot::CodeReviewGenerator.new(
        repo: @github_repo,
        pull: @github_pull,
        requestor: @owner,
      )
      generator.generate
    end

    test "returns a message that shows that no comments were generated for reviewed files", skip_enterprise: true do
      Failbot.expects(:report).never
      @github_pull.stubs(:changed_files).returns(2)

      excluded_file = {
        file_path: "pkg/codereviewagent/pullrequestreview.rbi",
        language: "Ruby",
        reason: "file_type_not_supported",
      }

      response = {
        choices: nil,
        copilot_references: [
          {
            type: "github.excluded-file",
            data: excluded_file,
            id: "",
            metadata: { display_name: "", display_icon: "" }
          }
        ]
      }

      fake_capi_user = mock("capi user", create_code_review: response)
      Copilot::User::CopilotApi.expects(:new).once.returns(fake_capi_user)

      fake_review_creator = mock("review creator")
      fake_review_creator.expects(:create).once.returns(true)
      PullRequests::Copilot::CodeReviewCreator.expects(:new).once.with(
        pull: @github_pull,
        repo: @github_repo,
        commit_id: @github_pull.head_sha,
        comments: [],
        diff_start_commit_oid: @github_pull.base_sha,
        diff_end_commit_oid: @github_pull.head_sha,
        diff_base_commit_oid: @github_pull.merge_base,
        body: regexp_matches(/Copilot reviewed 1 out of 2 changed files in this pull request and generated no comments/),
        return_with_error: false,
      ).returns(fake_review_creator)

      generator = PullRequests::Copilot::CodeReviewGenerator.new(
        repo: @github_repo,
        pull: @github_pull,
        requestor: @owner,
      )
      generator.generate
    end
  end
end
