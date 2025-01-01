# typed: true
# frozen_string_literal: true

require "test_helper"
require "json"

module PullRequests
  module PageData::Files::FileTree
    class LoaderTest < GitHub::TestCase
      include GitHub::QueryAssertionTestHelpers

      fixtures do
        @user = create(:user)
        repo = create(:repository, admin: @user, from_example: :review_comment_fork)
        create(:collaborator, collaborator: @user, repository: repo)
        assert repo.member?(@user)

        @pull = create(:pull_request,
          :with_mergeable_head,
          base_ref: repo.default_branch,
          base_repository: repo,
          base_user: @user,
          head_ref_name: "topic2",
          head_repository: repo,
          head_user: @user,
          repository: repo,
          user: @user,
        )

        assert_predicate @pull, :valid?

        @base_ref_oid = @pull.base_sha
        @end_commit_oid = @pull.head_sha
        @start_commit_oid = @pull.merge_base

        @pr_review = create(:pull_request_review, pull_request: @pull, user: @user, body: "this is good")
        @pr_review_thread = create(:pull_request_review_thread, pull_request: @pull, pull_request_review: @pr_review)
        @pr_review_comment = create(:pull_request_review_comment,
          pull_request: @pull,
          user: @user,
          pull_request_review: @pr_review,
          pull_request_review_thread: @pr_review_thread
        )

        @default_check_suite = create(
          :check_suite,
          repository: @pull.repository,
          head_sha: @pull.head_sha,
          head_branch: @pull.head_ref,
          name: "coverage"
        )
      end

      test "returns expected data for logged in user" do
        notice_annotation_check_run = create(:completed_check_run, check_suite: @default_check_suite, conclusion: :success)

        notice_annotation = create(
          :check_annotation,
          check_run: notice_annotation_check_run,
          path: "app/packages/ui/types.ts",
          annotation_level: "notice",
          start_line: 5,
          end_line: 7
        )

        pull_comparison = PullRequest::Comparison.find(
          base_commit_oid: @pull.base_sha,
          end_commit_oid: @end_commit_oid,
          pull: @pull,
          start_commit_oid: @start_commit_oid,
          viewer: @user,
        )

        actual_data = assert_query_counts(17) do
          PullRequests::PageData::Files::FileTree::Loader.load(
            comparison: pull_comparison,
            current_user: @user,
            pull_request: @pull,
            cap_filter: nil,
            user_session: nil,
            end_commit_oid: @end_commit_oid,
          )
        end.serialize

        expected_data = {
          "annotations" => [{ "annotation_level" => "notice", "path" => "app/packages/ui/types.ts" }],
          "base_ref_oid" => @base_ref_oid,
          "codeowners" => Repository::Codeowners.new(@pull.repository),
          "commits" => @pull.changed_commits,
          "diffs" => pull_comparison.diff.summary.deltas.map do |diff|
            {
              "diff_delta" => diff,
              "is_codeowner" => false,
              "tree_entry" => TreeEntry.new(@pull.repository, {
                "oid" => diff.new_file.oid,
                "path" => diff.new_file.path,
                "mode" => diff.new_file.mode,
                "type" => "blob",
              }),
            }
          end,
          "thread_previews" => { "bar.txt" => 1 },
          "pull_request" => @pull,
          "repository" => @pull.repository,
          "viewed_files" => PullRequestUserReviews.new(@pull, @user),
        }

        assert_equal expected_data["base_ref_oid"], actual_data["base_ref_oid"]
        assert_equal expected_data["commits"], actual_data["commits"]

        # GitHub::Diff::Entry objects cannot be compared directly, so we assert on path instead
        assert_equal expected_data["diffs"].map { |diff| diff["diff_delta"].path }, actual_data["diffs"].map { |diff| diff["diff_delta"].path }
        assert_equal expected_data["diffs"].map { |diff| diff["tree_entry"] }, actual_data["diffs"].map { |diff| diff["tree_entry"] }
        assert_equal expected_data["diffs"].map { |diff| diff["is_codeowner"] }, actual_data["diffs"].map { |diff| diff["is_codeowner"] }

        assert_equal expected_data["annotations"], actual_data["annotations"]
        assert_equal expected_data["thread_previews"], actual_data["thread_previews"]

        assert_same_elements expected_data["viewed_files"].reviewed_paths, actual_data["viewed_files"].reviewed_paths
      end

      test "returns expected data for a logged in user with a last review" do
        review = create(:pull_request_review, pull_request: @pull,
          user: @user,
          head_sha: @pull.head_sha,
          state: PullRequestReview.state_value(:commented)
        )

        pull_comparison = PullRequest::Comparison.find(
          base_commit_oid: @pull.base_sha,
          end_commit_oid: @end_commit_oid,
          pull: @pull,
          start_commit_oid: @start_commit_oid,
          viewer: @user,
        )

        actual_data = assert_query_counts(15) do
          PullRequests::PageData::Files::FileTree::Loader.load(
            comparison: pull_comparison,
            current_user: @user,
            pull_request: @pull,
            cap_filter: nil,
            user_session: nil,
            end_commit_oid: @end_commit_oid,
          )
        end.serialize

        expected_data = {
          "last_review_oid" => @pull.head_sha,
        }

        assert_equal expected_data["last_review_oid"], actual_data["last_review_oid"]
      end


      test "returns expected data for logged out user" do
        pull_comparison = PullRequest::Comparison.find(
          base_commit_oid: @pull.base_sha,
          end_commit_oid: @end_commit_oid,
          pull: @pull,
          start_commit_oid: @start_commit_oid,
          viewer: @user,
        )

        actual_data = assert_query_counts(12) do
          PullRequests::PageData::Files::FileTree::Loader.load(
            comparison: pull_comparison,
            pull_request: @pull,
            cap_filter: nil,
            user_session: nil,
            end_commit_oid: @end_commit_oid,
          )
        end.serialize

        expected_data = {
          "base_ref_oid" => @base_ref_oid,
          "codeowners" => Repository::Codeowners.new(@pull.repository),
          "commits" => @pull.changed_commits,
          "diffs" => pull_comparison.diff.summary.deltas.map do |diff|
            {
              "diff_delta" => diff,
              "is_codeowner" => false,
              "tree_entry" => TreeEntry.new(@pull.repository, {
                "oid" => diff.new_file.oid,
                "path" => diff.new_file.path,
                "mode" => diff.new_file.mode,
                "type" => "blob",
              }),
            }
          end,
          "viewed_files" => PullRequestUserReviews.new(@pull, @user),
        }

        assert_equal expected_data["base_ref_oid"], actual_data["base_ref_oid"]
        assert_equal expected_data["commits"], actual_data["commits"]

        # GitHub::Diff::Entry objects cannot be compared directly, so we assert on path instead
        assert_equal expected_data["diffs"].map { |diff| diff["diff_delta"].path }, actual_data["diffs"].map { |diff| diff["diff_delta"].path }
        assert_equal expected_data["diffs"].map { |diff| diff["tree_entry"] }, actual_data["diffs"].map { |diff| diff["tree_entry"] }
        assert_equal expected_data["diffs"].map { |diff| diff["is_codeowner"] }, actual_data["diffs"].map { |diff| diff["is_codeowner"] }

        assert_same_elements expected_data["viewed_files"].reviewed_paths, actual_data["viewed_files"].reviewed_paths
      end
    end
  end
end
