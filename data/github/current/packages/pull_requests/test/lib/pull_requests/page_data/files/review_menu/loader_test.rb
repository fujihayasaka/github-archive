# typed: true
# frozen_string_literal: true

require "test_helper"
require "json"

module PullRequests
  module PageData::Files::ReviewMenu
    class LoaderTest < GitHub::TestCase
      fixtures do
        @user = create(:user)

        @repository = create(:repository, admin: @user, from_example: :review_comment_fork)
        create(:collaborator, collaborator: @user, repository: @repository)
        assert @repository.member?(@user)

        @pull = create(:pull_request,
          repository: @repository,
          base_repository: @repository,
          base_user: @user,
          base_ref: @repository.default_branch,
          head_repository: @repository,
          head_user: @user,
          head_ref_name: "topic",
          user: @user,
        )

        @review = PullRequestReview.create(
          user: @user,
          pull_request: @pull,
          state: :pending,
          head_sha: @pull.head_sha,
        )
      end

      test "returns expected payload for logged in user with a comment" do
        comment = create(:pull_request_review_comment,
          pull_request: @pull,
          user: @user,
          body: "hiya",
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 26,
          pull_request_review: @review,
        )
        thread = comment.memoized_async_pull_request_review_thread.sync

        expected_payload = {
          "review" => @pull.latest_pending_review_for(@user),
          "review_comments" => [{
            "body_html" => comment.body_html,
            "id" => String(thread.id),
            "is_outdated" => false,
            "is_resolved" => false,
            "line" => 18,
            "path" => thread.path,
            "subject" => {
              "diff_lines" => thread.async_diff_lines(max_context_lines: 3).sync,
              "end_line" => 26,
              "end_diff_side" => "RIGHT",
              "original_end_line" => 18,
              "pull_request_commit" => @pull.head_sha,
              "start_diff_side" => "RIGHT",
              "start_line" => 26,
            },
            "subject_type" => "line",
            "thread_comments" => thread.comments.load_target
          }],
        }

        actual_payload = PullRequests::PageData::Files::ReviewMenu::Loader.load(
          current_user: @user,
          pull_request: @pull,
        )

        refute_nil actual_payload
        assert_equal expected_payload, actual_payload.serialize
      end

      test "returns expected payload for logged in user with no comments" do
        expected_payload = {
          "review" => @pull.latest_pending_review_for(@user),
          "review_comments" => [],
        }

        actual_payload = PullRequests::PageData::Files::ReviewMenu::Loader.load(
          current_user: @user,
          pull_request: @pull,
        )

        refute_nil actual_payload
        assert_equal expected_payload, actual_payload.serialize
      end

      test "returns expected payload for logged out user" do
        expected_payload = {
          "review_comments" => [],
        }

        actual_payload = PullRequests::PageData::Files::ReviewMenu::Loader.load(
          current_user: nil,
          pull_request: @pull,
        )
        assert_equal expected_payload, actual_payload.serialize
      end
    end
  end
end
