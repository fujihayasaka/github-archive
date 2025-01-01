# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Instrumentation
  class DiscussionsInstrumentationTest < GitHub::TestCase
    include HydroTestHelpers

    fixtures do
      @user = create(:user)
      @repo = create(:repository)
      category = create(:discussion_category, repository: @repo)
      @discussion = create(:discussion, repository: @repo, category: category)
      @discussion_comment = create(:discussion_comment, discussion: @discussion, body: "Beep boop beep, I'm a robot")
    end

    context "Create discussion" do
      test "hydro payload includes Discussion Scanning TSS feature flags" do

        expected_flags = %w[flag1 flag2 flag3]
        SecretScanning::Instrumentation::RepositoryServiceFlags.any_instance.stubs(:discussion_scanning_service_flags).returns(expected_flags)

        expected_message = {
          feature_flags: expected_flags,
        }

        GlobalInstrumenter.instrument(
          "discussion.create",
          actor: @user,
          repository: @repo,
          discussion: @discussion
        )
        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.discussions.v1.DiscussionCreate")
        end
      end
      test "discussion scan is published on create" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)
        expected_message = {
          content_id: @discussion.id,
          content_number: @discussion.number
        }

        GlobalInstrumenter.instrument(
          "discussion.create",
          actor: @user,
          repository: @repo,
          discussion: @discussion
        )
        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end
    end

    context "Update discussion" do
      test "hydro payload includes Discussion Scanning TSS feature flags" do

        expected_flags = %w[flag1 flag2 flag3]
        SecretScanning::Instrumentation::RepositoryServiceFlags.any_instance.stubs(:discussion_scanning_service_flags).returns(expected_flags)

        expected_message = {
          feature_flags: expected_flags,
        }

        GlobalInstrumenter.instrument(
          "discussion.update",
          actor: @user,
          repository: @repo,
          discussion: @discussion,
          #previous_body: "old body"
        )

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.discussions.v1.DiscussionUpdate")
        end
      end
      test "discussion scan is published on update" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)
        expected_message = {
          content_id: @discussion.id,
          content_number: @discussion.number
        }

        GlobalInstrumenter.instrument(
          "discussion.update",
          actor: @user,
          repository: @repo,
          discussion: @discussion,
        )
        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end
    end

    context "Create discussion comment" do
      test "hydro payload includes Discussion Scanning TSS feature flags" do

        expected_flags = %w[flag1 flag2 flag3]
        SecretScanning::Instrumentation::RepositoryServiceFlags.any_instance.stubs(:discussion_scanning_service_flags).returns(expected_flags)

        expected_message = {
          feature_flags: expected_flags,
        }

        GlobalInstrumenter.instrument(
          "discussion_comment.create",
          actor: @user,
          repository: @repo,
          discussion: @discussion,
          discussion_comment: @discussion_comment
        )

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.discussions.v1.DiscussionCommentCreate")
        end
      end
      test "discussion comment scan is published on create" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)
        expected_message = {
          content_id: @discussion_comment.id,
          content_number: @discussion.number
        }

        GlobalInstrumenter.instrument(
          "discussion_comment.create",
          actor: @user,
          repository: @repo,
          discussion: @discussion,
          discussion_comment: @discussion_comment
        )
        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end
    end

    context "Update discussion comment" do
      test "hydro payload includes Issue Scanning TSS feature flags" do

        expected_flags = %w[flag1 flag2 flag3]
        SecretScanning::Instrumentation::RepositoryServiceFlags.any_instance.stubs(:discussion_scanning_service_flags).returns(expected_flags)

        expected_message = {
          feature_flags: expected_flags,
        }

        GlobalInstrumenter.instrument(
          "discussion_comment.update",
          actor: @user,
          repository: @repo,
          discussion: @discussion,
          discussion_comment: @discussion_comment
        )

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.discussions.v1.DiscussionCommentUpdate")
        end
      end
      test "discussion comment scan is published on update" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)
        expected_message = {
          content_id: @discussion_comment.id,
          content_number: @discussion.number
        }

        GlobalInstrumenter.instrument(
          "discussion_comment.update",
          actor: @user,
          repository: @repo,
          discussion: @discussion,
          discussion_comment: @discussion_comment
        )
        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end
    end
  end
end
