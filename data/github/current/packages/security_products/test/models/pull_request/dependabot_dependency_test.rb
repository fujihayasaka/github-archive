# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequest::DependabotDependencyTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers
  include GitHub::PullRequestTestHelpers

  fixtures do
    GitHub::Enterprise.ensure_business! if GitHub.enterprise?

    @org = create(:organization)
    @owner = @org.admins.first

    make_trusted_oauth_apps_owner
    @dependabot_app = create(:dependabot_integration)
    @repo = create(:private_repository, owner: @org, from_example: :review_comment_fork)

    base_ref = @repo.heads.find("master")
    base_ref.append_commit({ message: "commit on default", committer: @owner }, @owner) do |files|
      files.add("main.js", "const axios = require('axios');\n console.log(axios);\n")
    end
  end

  setup do
    @branch_name = "dependabot/npm_and_yarn/axios-1.7.7"
    master_branch = @repo.heads.find("master")

    # Always set @pr_branch_ref, whether branch exists or not
    @pr_branch_ref = @repo.heads.find(@branch_name) ||
                     @repo.heads.create(@branch_name, master_branch.target, @dependabot_app.bot)

    # Append a commit on the feature branch
    @pr_branch_ref.append_commit({ message: "Update package.json", committer: @dependabot_app.bot }, @dependabot_app.bot) do |files|
      files.add("package.json", 10.times.map(&:to_s).join("\n"))
    end

    @pull_request = make_pr(@repo, @repo, branch: @branch_name)
    @pull_request.create_merge_commit

    @check_suite = CheckSuite.create!(
      repository: @repo,
      head_sha: @pull_request.head_sha,
      status: "completed",
      conclusion: "success",
      github_app_id: Apps::Privileged.integration_id(:dependabot)
    )

    @check_run = CheckRun.create!(
      check_suite: @check_suite,
      name: PullRequest::DependabotDependency::CHECK_RUN_NAME,
      repository: @repo,
    )

    @review = @pull_request.reviews.create!(
      user: @dependabot_app.bot,
      head_sha: @pull_request.head_sha,
      variant_type: "dependabot"
    )

    @comment = create(:pull_request_review_comment,
      pull_request: @pull_request,
      pull_request_review: @review,
      user: @dependabot_app.bot,
      commit_id: @pull_request.head_sha,
      path: "package.json",
      original_position: 1,
      blob_position: 1,
      body: "Breaking change",
    )

    @review.comment!
    @comment.reload

    @repo.owner

    # Additional annotation setup
    annotation_attributes = {
      autofix_job_id: 2343445,
      level: "failure",
      message: "The method _.pluck has been removed from the lodash library in version 4.17.21",
      locations: [{
        artifactLocation: "package.json",
        startLine: 132,
        endLine: 132,
        startColumn: 1,
        endColumn: 24
      }]
    }

    @annotation = Dependabot::AnnotationCreator.new
    @annotation_count = @annotation.create_annotations(@check_run, annotation_attributes)
    @dependabot_annotation = @check_run.annotations.first
  end

  teardown do
    # Delete the branch after each test as getting "Git::Ref::ExistsError" error
    @repo.heads.find(@branch_name)&.delete(@dependabot_app.bot)
  end

  # Mock the Twirp response for `get_suggested_fix`
  def dependabot_suggested_fix_response
    DependabotApi::V1::GetSuggestedFixResponse.new(
      suggested_fix: DependabotApi::V1::SuggestedFix.new(
        id: 1,
        autofix_job_id: 2343445,
        description: "Require axios default export",
        files: [
          DependabotApi::V1::SuggestedFixFile.new(
            file_path: "main.js",
            diff_content: "diff --git a/main.js b/main.js\nindex 0000000..1111111 100644\n--- a/main.js\n+++ b/main.js\n@@ -1,2 +1,2 @@\n-const axios = require('axios');\n+const axios = require('axios').default;\n console.log(axios);\n"
          )
        ],
        review_status: DependabotApi::V1::SuggestedFix::SuggestedFixReviewStatus::STATUS_UNREVIEWED,
        dependency_metadata: []
      )
    )
  end

  test "dependabot_annotation_for_review_comment returns correct annotation" do
    @pull_request.update!(head_sha: "DEADBEEF")
    annotation = @pull_request.dependabot_annotation_for_review_comment(@comment)

    assert_equal @dependabot_annotation.id, annotation.id
    assert_equal @dependabot_annotation.filename, annotation.filename
    assert_equal @dependabot_annotation.message, annotation.message
  end

  test "dependabot_review_comment_for_comment creates review comment" do
    review_comment = @pull_request.dependabot_review_comment_for_comment(@comment, @pull_request.number)

    assert_equal review_comment.id, @dependabot_annotation.id
    assert_equal review_comment.autofix_job_id, @dependabot_annotation.dependabot_annotation.autofix_job_id
    assert_equal review_comment.warning_level, @dependabot_annotation.warning_level
  end

  test "dependabot_review_comment_for_comment is resilient to a missing annotation" do
    CheckAnnotation.any_instance.stubs(:dependabot_annotation).returns(nil)
    review_comment = @pull_request.dependabot_review_comment_for_comment(@comment, @pull_request.number)

    assert_nil review_comment.autofix_job_id
    assert_equal review_comment.warning_level, @dependabot_annotation.warning_level
  end

  test "dependabot_suggested_fix_autofix_job returns suggested fix" do
    Dependabot::Twirp.suggested_fixes_client.expects(:get_suggested_fix).returns(dependabot_suggested_fix_response)

    dependabot_review_comment = @pull_request.dependabot_review_comment_for_comment(@comment, @pull_request.number)

    suggested_fix = @pull_request.dependabot_suggested_fix_autofix_job(dependabot_review_comment)

    refute_nil suggested_fix
    assert_equal @dependabot_annotation.dependabot_annotation.autofix_job_id, suggested_fix.autofix_job_id
  end

  test "async_dependabot_suggested_fixes returns correct promise response" do
    Dependabot::Twirp.suggested_fixes_client.expects(:get_suggested_fix).returns(dependabot_suggested_fix_response)

    dependabot_review_comment = @pull_request.dependabot_review_comment_for_comment(@comment, @pull_request.number)

    promise = @pull_request.async_dependabot_suggested_fixes(dependabot_review_comment)
    result = promise.sync

    assert_equal @dependabot_annotation.dependabot_annotation.autofix_job_id, result.autofix_job_id
    assert_equal "Require axios default export", result.description
  end

  test "async_dependabot_suggested_fixes is resilient to twirp errors" do
    Dependabot::Twirp.suggested_fixes_client.expects(:get_suggested_fix).raises(Dependabot::Twirp::ServiceUnavailableError)

    dependabot_review_comment = @pull_request.dependabot_review_comment_for_comment(@comment, @pull_request.number)

    promise = assert_nothing_raised do
      @pull_request.async_dependabot_suggested_fixes(dependabot_review_comment)
    end

    result = promise.sync
    assert_nil result
  end

  test "dependabot_review_comment_for_comment returns nil when user is not Dependabot" do
    # Create a new comment by a user who is not Dependabot
    non_dependabot_user = create(:user, login: "non-dependabot-user")

    @review = @pull_request.reviews.create!(
      user: non_dependabot_user,
      head_sha: @pull_request.head_sha,
      variant_type: "dependabot"
    )

    @non_dependabot_comment = create(:pull_request_review_comment,
      pull_request: @pull_request,
      pull_request_review: @review,
      user: non_dependabot_user,
      commit_id: @pull_request.head_sha,
      path: "package.json",
      original_position: 1,
      blob_position: 1,
      body: "Breaking change",
    )

    review_comment = @pull_request.dependabot_review_comment_for_comment(@non_dependabot_comment, @pull_request.number)
    assert_nil review_comment, "Expected nil when the review comment is not from Dependabot"
  end
end
