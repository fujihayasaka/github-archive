# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Instrumentation
  class PullRequestsInstrumentationTest < GitHub::TestCase
    include HydroTestHelpers

    fixtures do
      @user = create(:user)
      @repo = create(:repository, owner: @user, from_example: :pull_request_fork)
      category = create(:discussion_category, repository: @repo)
      @issue = create(:issue, user: @user, repository: @repo)
      @pull_request = create(:pull_request, repository: @repo, issue: @issue, user: @user)
      @issue_comment = create(:issue_comment, user: @user, issue: @issue)
      @pull_request_review_comment = create(:pull_request_review_comment, pull_request: @pull_request, user: @user, body: "ship it")
      @pull_request_review_thread = create(:pull_request_review_thread, pull_request: @pull_request)
      @pull_request_review = create(:pull_request_review, pull_request: @pull_request, user: @user)
    end

    context "Pull Request Create" do
      test "hydro payload includes Pull Requests Scanning TSS feature flags" do

        expected_flags = %w[flag1 flag2 flag3]
        SecretScanning::Instrumentation::RepositoryServiceFlags.any_instance.stubs(:pull_request_scanning_service_flags).returns(expected_flags)

        expected_message = {
          feature_flags: expected_flags,
        }

        GlobalInstrumenter.instrument(
          "pull_request.create",
          actor: @user,
          repository: @repo,
          pull_request: @pull_request,
        )
        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.v1.PullRequestCreate")
        end
      end
      test "pull request scan is published on create" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)
        expected_message = {
          content_id: @pull_request.issue.id,
          content_number: @pull_request.number
        }

        GlobalInstrumenter.instrument(
          "pull_request.create",
          actor: @user,
          repository: @repo,
          pull_request: @pull_request,
        )
        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end
    end

    context "Pull Request Update" do
      test "hydro payload includes Pull Requests Scanning TSS feature flags" do

        expected_flags = %w[flag1 flag2 flag3]
        SecretScanning::Instrumentation::RepositoryServiceFlags.any_instance.stubs(:pull_request_scanning_service_flags).returns(expected_flags)

        expected_message = {
          feature_flags: expected_flags,
        }

        GlobalInstrumenter.instrument(
          "issue.update",
          actor: @user,
          repository: @repo,
          issue: @issue,
        )
        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.v1.PullRequestUpdate")
        end
      end
      test "pull request scan is published on update" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)
        expected_message = {
          content_id: @pull_request.issue.id,
          content_number: @pull_request.number
        }

        GlobalInstrumenter.instrument(
          "issue.update",
          actor: @user,
          repository: @repo,
          issue: @issue,
        )
        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end
    end

    context "Pull Request Timeline Comment Create" do
      test "hydro payload includes Pull Requests Scanning TSS feature flags" do

        expected_flags = %w[flag1 flag2 flag3]
        SecretScanning::Instrumentation::RepositoryServiceFlags.any_instance.stubs(:pull_request_scanning_service_flags).returns(expected_flags)

        expected_message = {
          feature_flags: expected_flags,
        }

        GlobalInstrumenter.instrument(
          "issue_comment.create",
          actor: @user,
          repository: @repo,
          issue_comment: @issue_comment,
          issue: @issue
        )
        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.v1.PullRequestTimelineCommentCreate")
        end
      end
      test "pull request comment scan is published on create" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)
        expected_message = {
          content_id: @issue_comment.id,
          content_number: @pull_request.number
        }

        GlobalInstrumenter.instrument(
          "issue_comment.create",
          actor: @user,
          repository: @repo,
          issue_comment: @issue_comment,
          issue: @issue
        )
        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end
    end

    context "Pull Request Timeline Comment Update" do
      test "hydro payload includes Pull Requests Scanning TSS feature flags" do

        expected_flags = %w[flag1 flag2 flag3]
        SecretScanning::Instrumentation::RepositoryServiceFlags.any_instance.stubs(:pull_request_scanning_service_flags).returns(expected_flags)

        expected_message = {
          feature_flags: expected_flags,
        }

        GlobalInstrumenter.instrument(
          "issue_comment.update",
          actor: @user,
          repository: @repo,
          issue_comment: @issue_comment,
          issue: @issue
        )
        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.v1.PullRequestTimelineCommentUpdate")
        end
      end
      test "pull request comment scan is published on update" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)
        expected_message = {
          content_id: @issue_comment.id,
          content_number: @pull_request.number
        }

        GlobalInstrumenter.instrument(
          "issue_comment.update",
          actor: @user,
          repository: @repo,
          issue_comment: @issue_comment,
          issue: @issue
        )
        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end
    end

    context "Pull Request Review Comment Create" do
      test "hydro payload includes Pull Requests Scanning TSS feature flags" do

        expected_flags = %w[flag1 flag2 flag3]
        SecretScanning::Instrumentation::RepositoryServiceFlags.any_instance.stubs(:pull_request_scanning_service_flags).returns(expected_flags)

        expected_message = {
          feature_flags: expected_flags,
        }

        GlobalInstrumenter.instrument(
          "pull_request_review_comment.create",
          actor: @user,
          repository: @repo,
          pull_request: @pull_request,
          review_comment: @pull_request_review_comment,
        )
        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.v1.PullRequestReviewCommentCreate")
        end
      end
      test "pull request review comment scan is published on create" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)
        expected_message = {
          content_id: @pull_request_review_comment.id,
          content_number: @pull_request.number
        }

        GlobalInstrumenter.instrument(
          "pull_request_review_comment.create",
          actor: @user,
          repository: @repo,
          pull_request: @pull_request,
          review_comment: @pull_request_review_comment,
        )
        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end
    end

    context "Pull Request Review Comment Update" do
      test "hydro payload includes Pull Requests Scanning TSS feature flags" do

        expected_flags = %w[flag1 flag2 flag3]
        SecretScanning::Instrumentation::RepositoryServiceFlags.any_instance.stubs(:pull_request_scanning_service_flags).returns(expected_flags)

        expected_message = {
          feature_flags: expected_flags,
        }

        GlobalInstrumenter.instrument(
          "pull_request_review_comment.update",
          actor: @user,
          repository: @repo,
          pull_request: @pull_request,
          review_comment: @pull_request_review_comment,
        )
        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.v1.PullRequestReviewCommentUpdate")
        end
      end
      test "pull request review comment scan is published on update" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)
        expected_message = {
          content_id: @pull_request_review_comment.id,
          content_number: @pull_request.number
        }

        GlobalInstrumenter.instrument(
          "pull_request_review_comment.update",
          actor: @user,
          repository: @repo,
          pull_request: @pull_request,
          review_comment: @pull_request_review_comment,
        )
        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end
    end

    context "Pull Request Review Submit" do
      test "hydro payload includes Pull Requests Scanning TSS feature flags" do

        expected_flags = %w[flag1 flag2 flag3]
        SecretScanning::Instrumentation::RepositoryServiceFlags.any_instance.stubs(:pull_request_scanning_service_flags).returns(expected_flags)

        expected_message = {
          feature_flags: expected_flags,
        }
        GlobalInstrumenter.instrument(
          "pull_request_review.submit",
          actor: @user,
          pull_request: @pull_request,
          pull_request_review_thread: @pull_request_review_thread,
          review: @pull_request_review,
        )
        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.v1.PullRequestReviewSubmit")
        end
      end
      test "pull request review scan is published on submit" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)
        expected_message = {
          content_id: @pull_request_review.id,
          content_number: @pull_request.number
        }

        GlobalInstrumenter.instrument(
          "pull_request_review.submit",
          actor: @user,
          pull_request: @pull_request,
          pull_request_review_thread: @pull_request_review_thread,
          review: @pull_request_review,
        )
        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end
    end

    context "Pull Request Review Update" do
      test "hydro payload includes Pull Requests Scanning TSS feature flags" do

        expected_flags = %w[flag1 flag2 flag3]
        SecretScanning::Instrumentation::RepositoryServiceFlags.any_instance.stubs(:pull_request_scanning_service_flags).returns(expected_flags)

        expected_message = {
          feature_flags: expected_flags,
        }
        GlobalInstrumenter.instrument(
          "pull_request_review.update",
          actor: @user,
          pull_request: @pull_request,
          pull_request_review_thread: @pull_request_review_thread,
          review: @pull_request_review,
        )
        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.v1.PullRequestReviewEdit")
        end
      end
      test "pull request review scan is published on update" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)
        expected_message = {
          content_id: @pull_request_review.id,
          content_number: @pull_request.number
        }

        GlobalInstrumenter.instrument(
          "pull_request_review.update",
          actor: @user,
          pull_request: @pull_request,
          pull_request_review_thread: @pull_request_review_thread,
          review: @pull_request_review,
        )
        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end
    end
  end
end
