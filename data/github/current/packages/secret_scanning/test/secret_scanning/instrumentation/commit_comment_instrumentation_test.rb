# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Instrumentation
  class CommitCommentInstrumentationTest < GitHub::TestCase
    include HydroTestHelpers

    fixtures do
      @user = create(:user)
      @repo = create(:repository)
      @commit_comment = create(:commit_comment, repository: @repo)
    end

    context "Commit Comment Create" do
      test "hydro payload includes Commit Comment Scanning TSS feature flags" do

        expected_flags = %w[flag1 flag2 flag3]
        SecretScanning::Instrumentation::RepositoryServiceFlags.any_instance.stubs(:commit_comment_scanning_service_flags).returns(expected_flags)

        expected_message = {
          feature_flags: expected_flags,
        }

        GlobalInstrumenter.instrument(
          "commit_comment.create",
          actor: @user,
          repository: @repo,
          commit_comment: @commit_comment,
        )
        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.v1.CommitCommentCreate")
        end
      end
    end

    context "Commit Comment Update" do
      test "hydro payload includes Commit Comment Scanning TSS feature flags" do

        expected_flags = %w[flag1 flag2 flag3]
        SecretScanning::Instrumentation::RepositoryServiceFlags.any_instance.stubs(:commit_comment_scanning_service_flags).returns(expected_flags)

        expected_message = {
          feature_flags: expected_flags,
        }

        GlobalInstrumenter.instrument(
          "commit_comment.update",
          actor: @user,
          repository: @repo,
          commit_comment: @commit_comment,
        )
        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.v1.CommitCommentUpdate")
        end
      end
    end



  end
end
