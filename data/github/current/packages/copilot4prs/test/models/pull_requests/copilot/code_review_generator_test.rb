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

    base_ref = @repo.heads.find("master")
    head_ref = @repo.heads.create("topic", base_ref.target, @repo.owner)
    head_ref.append_commit({
      message: "a change",
      committer: @repo.owner,
    }, @repo.owner) do |files|
      content = "// PullRequestReview reprsents a review that contains comments from Copilot."
      files.add("file1", content)
    end

    @pull_with_error_comments = PullRequest.create_for! @repo, user: @owner, base: "master", head: "topic", title: "asdf", body: "asdf"

    make_trusted_oauth_apps_owner
    integration = Apps::Privileged::CopilotPullRequestReviewer.seed_database!
    PrivilegedAppHelper.reconfigure_privileged_app(app_alias: :copilot_pull_request_reviewer, app: integration)
    @bot = ::Apps::Privileged.integration(:copilot_pull_request_reviewer).bot
  end

  setup do
    PullRequests::Copilot::CodeReviewAccess.any_instance.stubs(:can_create_review_request?).returns(true)
    GitHub.flipper[:expand_supported_languages_cpp].disable
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
      body: regexp_matches(/Copilot reviewed 1 out of 1 changed files in this pull request and generated 1 suggestion/),
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
    @repo.owner.enable_feature(:expand_supported_languages_cpp)
    serializer = Copilot::PullRequests::CodeReviewReferenceSerializer.new
    pr_ref = serializer.to_hash(@pull, include_diff: true, include_full_files: true)

    Copilot::User::CopilotApi.any_instance.expects(:create_code_review).with(
      references: [pr_ref],
      role: "user",
      experiment_headers: { "X-Experiment-Expand-Supported-Languages-Cpp" => "true" },
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

  test "Should return error comment if CopilotApi::UnauthorizedError occurs", skip_enterprise: true do
    message = PullRequests::Copilot::CodeReviewCreator::ERROR_COMMENTS

    GitHub.flipper[:copilot_code_reviews_internal_feedback_advert].enable
    GitHub.flipper[:copilot_pr_reviews_submit_error].enable

    Copilot::User::CopilotApi.any_instance.stubs(:get_knowledge_base).raises(CopilotAPI::UnauthorizedError)

    @github_pull.review_requests.create(reviewer: @bot)

    generator = PullRequests::Copilot::CodeReviewGenerator.new(
      repo: @github_repo,
      pull: @github_pull,
      requestor: @owner,
    )
    assert generator.generate, "expected review persistence to succeed"

    assert_equal message, @github_pull.reviews.first.body
  end

  test "Should return error comment if CopilotApi::NotFoundError occurs", skip_enterprise: true do
    message = PullRequests::Copilot::CodeReviewCreator::ERROR_COMMENTS

    GitHub.flipper[:copilot_code_reviews_internal_feedback_advert].enable
    GitHub.flipper[:copilot_pr_reviews_submit_error].enable

    Copilot::User::CopilotApi.any_instance.stubs(:get_knowledge_base).raises(CopilotAPI::NotFoundError.new)

    @github_pull.review_requests.create(reviewer: @bot)

    Copilot::User::CopilotApi.expects(:new).once.raises(CopilotAPI::NotFoundError.new)

    generator = PullRequests::Copilot::CodeReviewGenerator.new(
      repo: @github_repo,
      pull: @github_pull,
      requestor: @owner,
    )
    assert generator.generate, "expected review persistence to succeed"

    assert_equal message, @github_pull.reviews.first.body
  end

  test "Should return NO error comment if copilot has no comments", skip_enterprise: true do
    message = PullRequests::Copilot::CodeReviewCreator::ERROR_COMMENTS
    message_no_files = PullRequests::Copilot::ReviewBodyMessageGenerator::NO_FILES_BODY

    GitHub.flipper[:copilot_code_reviews_internal_feedback_advert].enable
    GitHub.flipper[:copilot_pr_reviews_submit_error].enable
    GitHub.flipper[:copilot_pr_reviews_submit_empty_reviews].enable

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

  test "Destroy any existing review if process fails", skip_enterprise: true do
    Failbot.expects(:report).never

    # Create review request
    @pull.review_requests.create(reviewer: @bot)

    comment = {
      path: "pkg/codereviewagent/pullrequestreview.go",
      line: 17,
      body: "The word 'reprsents' should be corrected to 'represents'.\n```suggestion\n    // PullRequestReview represents a review that contains comments from Copilot.\n```",
      side: "RIGHT",
    }

    assert_empty @pull.reviews

    # results in an error because comment is an invalid type
    crc = PullRequests::Copilot::CodeReviewCreator.new(
      pull: @pull,
      repo: @repo,
      commit_id: @pull.head_sha,
      comments: [comment],
      diff_start_commit_oid: @pull.base_sha,
      diff_end_commit_oid: @pull.head_sha,
      diff_base_commit_oid: @pull.merge_base,
      body: nil,
      return_with_error: false,
    ).create

    assert_empty @pull.reviews.reload
    refute crc
  end

  test "Destroy the review when no commments were generated", skip_enterprise: true do
    Failbot.expects(:report).never

    # Create review request
    @pull.review_requests.create(reviewer: @bot)

    comment1 = {
      path: "pkg/codereviewagent/pullrequestreview.go",
      line: 17,
      body: "The word 'reprsents' should be corrected to 'represents'.\n```suggestion\n    // PullRequestReview represents a review that contains comments from Copilot.\n```",
      side: "RIGHT",
    }

    comment2 = {
      path: "pkg/codereviewagent/pullrequestreview.go",
      line: 25,
      body: "another comment from copilot",
      side: "RIGHT",
    }

    assert_empty @pull.reviews

    # results in an error because comment is an invalid type
    crc = PullRequests::Copilot::CodeReviewCreator.new(
      pull: @pull,
      repo: @repo,
      commit_id: @pull.head_sha,
      comments: [comment1, comment2],
      diff_start_commit_oid: @pull.base_sha,
      diff_end_commit_oid: @pull.head_sha,
      diff_base_commit_oid: @pull.merge_base,
      body: nil,
      return_with_error: false,
    ).create

    assert_empty @pull.reviews.reload
    refute crc
  end

  test "Review still posted even if some comments could not be generated", skip_enterprise: true do
    Failbot.expects(:report).never

    # Create review request
    @pull_with_error_comments.review_requests.create(reviewer: @bot)

    valid_comment = {
      path: "file1",
      line: 1,
      body: "The word 'reprsents' should be corrected to 'represents'.\n```suggestion\n    // PullRequestReview represents a review that contains comments from Copilot.\n```",
      side: "RIGHT",
      type: "spelling",
    }

    invalid_comment = {
      path: "pkg/codereviewagent/pullrequestreview.go",
      line: 25,
      body: "another comment from copilot",
      side: "RIGHT",
    }

    assert_empty @pull_with_error_comments.reviews

    crc = PullRequests::Copilot::CodeReviewCreator.new(
      pull: @pull_with_error_comments,
      repo: @repo,
      commit_id: @pull_with_error_comments.head_sha,
      comments: [valid_comment, invalid_comment],
      diff_start_commit_oid: @pull_with_error_comments.base_sha,
      diff_end_commit_oid: @pull_with_error_comments.head_sha,
      diff_base_commit_oid: @pull_with_error_comments.merge_base,
      body: nil,
      return_with_error: false,
    ).create

    @pull_with_error_comments.reviews.reload
    assert_equal 1, @pull_with_error_comments.reviews.length
    assert_equal 1, @pull_with_error_comments.reviews.first.review_comments.length
    assert crc
  end

  test "Adds note for comments generated by coding guidelines", skip_enterprise: true do
    Failbot.expects(:report).never

    # Create review request
    @pull_with_error_comments.review_requests.create(reviewer: @bot)

    custom_comment = {
      path: "file1",
      line: 1,
      body: "The word 'reprsents' should be corrected to 'represents'.\n```suggestion\n    // PullRequestReview represents a review that contains comments from Copilot.\n```",
      side: "RIGHT",
      type: "spelling",
      problem_type: "custom",
    }

    regular_comment = {
      path: "file1",
      line: 1,
      body: "The word 'reprsents' should be corrected to 'represents'.\n```suggestion\n    // PullRequestReview represents a review that contains comments from Copilot.\n```",
      side: "RIGHT",
      type: "spelling",
      problem_type: "foo",
    }

    assert_empty @pull_with_error_comments.reviews

    crc = PullRequests::Copilot::CodeReviewCreator.new(
      pull: @pull_with_error_comments,
      repo: @repo,
      commit_id: @pull_with_error_comments.head_sha,
      comments: [custom_comment, regular_comment],
      diff_start_commit_oid: @pull_with_error_comments.base_sha,
      diff_end_commit_oid: @pull_with_error_comments.head_sha,
      diff_base_commit_oid: @pull_with_error_comments.merge_base,
      body: nil,
    ).create

    @pull_with_error_comments.reviews.reload
    assert_equal 1, @pull_with_error_comments.reviews.length
    assert_equal 2, @pull_with_error_comments.reviews.first.review_comments.length

    custom_comment = @pull_with_error_comments.reviews.first.review_comments.first
    assert_match /This comment was generated based on a coding guideline created by a repository admin/, custom_comment.body

    regular_comment = @pull_with_error_comments.reviews.first.review_comments.last
    refute_match /This comment was generated based on a coding guideline created by a repository admin/, regular_comment.body

    assert crc
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
        body: regexp_matches(/Copilot reviewed 1 out of 2 changed files in this pull request and generated 1 suggestion/),
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
        body: regexp_matches(/Copilot reviewed 1 out of 2 changed files in this pull request and generated no suggestions/),
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
