# typed: true
# frozen_string_literal: true

require "test_helper"
require "json"

module PullRequests
  module PageData::Files::Toolbar
    class LoaderTest < GitHub::TestCase
      fixtures do
        @user = create(:user)
        @user.split_diff_preferred = "split"
        @user_session = create(:authentication_record, user: @user).user_session

        @repository = create(:repository, admin: @user, from_example: :review_comment_fork)
        create(:collaborator, collaborator: @user, repository: @repository)
        assert @repository.member?(@user)

        @reviewer = create(:user)
        @repository.add_member(@reviewer)
        @reviewer_session = create(:authentication_record, user: @reviewer).user_session

        @pull = create(:pull_request,
          :with_mergeable_head,
          repository: @repository,
          base_repository: @repository,
          base_user: @user,
          base_ref: @repository.default_branch,
          head_repository: @repository,
          head_user: @user,
          head_ref_name: "topic2",
          user: @user,
        )

        UserReviewedFile.create(
          filepath: "bar.txt",
          user: @user,
          pull_request: @pull,
          head_sha: @pull.head_sha,
        )

        PullRequestReview.create(
          user: @user,
          pull_request: @pull,
          state: :pending,
          head_sha: @pull.head_sha,
        )

        example_repo_snapshot
      end

      test "returns expected payload for logged in user" do
        Timecop.freeze do # Freeze the time to avoid flakiness of the generated alive channel
          enable_feature_flag(:copilot_workspace)

          expected_payload = {
            "annotations" => [],
            "copilot_access_allowed" => true,
            "current_user" => @user,
            "is_file_tree_expanded" => true,
            "pull_request" => {
              "alive_channel" => GitHub::WebSocket::Channels.signed_pull_request(@pull),
              "author" => @user,
              "historical_comparison" => {
                "base_oid" => @pull.historical_comparison.async_base_oid.sync,
                "head_oid" => @pull.historical_comparison.async_head_oid.sync
              },
              "id" => @pull.global_relay_id,
              "path_name" => @pull.permalink(include_host: false),
              "repository" => @repository,
              "state" => :open,
              "viewer_can_leave_non_comment_reviews" => false,
              "viewer_has_violated_push_policy" => false,
              "viewer_permission" => "write"
            },
            "should_show_viewed_files_count" => true,
            "thread_previews" => [],
            "total_files_count" => 1,
            "viewed_files_count" => 1,
            "viewer_pending_review" => {
              "review" => @pull.latest_pending_review_for(@user),
              "review_comments" => [],
            },
            "view_settings" => {
              "hide_whitespace" => false,
              "line_spacing" => "relaxed",
              "split_preference" => "split",
              "comments_preference" => "visible",
            },
          }

          pull_comparison = PullRequest::Comparison.find(
            base_commit_oid: @pull.base_sha,
            end_commit_oid: @pull.head_sha,
            pull: @pull,
            start_commit_oid: @pull.merge_base,
            viewer: @user,
          )

          actual_payload = PullRequests::PageData::Files::Toolbar::Loader.load(
            cap_filter: nil,
            comparison: pull_comparison,
            current_user: @user,
            end_commit_oid: @pull.head_sha,
            pull_request: @pull,
            user_session: @user_session
          )
          assert_equal expected_payload, actual_payload.serialize
        end
      end

      test "returns expected payload for logged in user that is not the author" do
        Timecop.freeze do # Freeze the time to avoid flakiness of the generated alive channel
          disable_feature_flag(:copilot_workspace)

          expected_payload = {
            "annotations" => [],
            "copilot_access_allowed" => false,
            "current_user" => @reviewer,
            "is_file_tree_expanded" => true,
            "pull_request" => {
              "alive_channel" => GitHub::WebSocket::Channels.signed_pull_request(@pull),
              "author" => @user,
              "historical_comparison" => {
                "base_oid" => @pull.historical_comparison.async_base_oid.sync,
                "head_oid" => @pull.historical_comparison.async_head_oid.sync
              },
              "id" => @pull.global_relay_id,
              "path_name" => @pull.permalink(include_host: false),
              "repository" => @repository,
              "state" => :open,
              "viewer_can_leave_non_comment_reviews" => true,
              "viewer_has_violated_push_policy" => false,
              "viewer_permission" => "write"
            },
            "should_show_viewed_files_count" => true,
            "thread_previews" => [],
            "total_files_count" => 1,
            "viewed_files_count" => 0,
            "viewer_pending_review" => { "review_comments" => [] },
            "view_settings" => {
              "hide_whitespace" => false,
              "line_spacing" => "relaxed",
              "split_preference" => "unified",
              "comments_preference" => "visible",
            },
          }

          pull_comparison = PullRequest::Comparison.find(
            base_commit_oid: @pull.base_sha,
            end_commit_oid: @pull.head_sha,
            pull: @pull,
            start_commit_oid: @pull.merge_base,
            viewer: @user,
          )

          actual_payload = PullRequests::PageData::Files::Toolbar::Loader.load(
            cap_filter: nil,
            comparison: pull_comparison,
            current_user: @reviewer,
            end_commit_oid: @pull.head,
            pull_request: @pull,
            user_session: @reviewer_session
          )

          assert_equal expected_payload, actual_payload.serialize
        end
      end

      test "returns expected payload for logged out user" do
        Timecop.freeze do # Freeze the time to avoid flakiness of the generated alive channel
          expected_payload = {
            "annotations" => [],
            "copilot_access_allowed" => false,
            "is_file_tree_expanded" => true,
            "pull_request" => {
              "alive_channel" => GitHub::WebSocket::Channels.signed_pull_request(@pull),
              "author" => @user,
              "historical_comparison" => {
                "base_oid" => @pull.historical_comparison.async_base_oid.sync,
                "head_oid" => @pull.historical_comparison.async_head_oid.sync
              },
              "id" => @pull.global_relay_id,
              "path_name" => @pull.permalink(include_host: false),
              "repository" => @repository,
              "state" => :open,
              "viewer_can_leave_non_comment_reviews" => false,
              "viewer_has_violated_push_policy" => false,
              "viewer_permission" => "read",
            },
            "should_show_viewed_files_count" => false,
            "thread_previews" => [],
            "total_files_count" => 1,
            "viewed_files_count" => 0,
            "viewer_pending_review" => { "review_comments" => [] },
            "view_settings" => {
              "hide_whitespace" => false,
              "line_spacing" => "relaxed",
              "split_preference" => "unified",
              "comments_preference" => "visible",
            },
          }

          pull_comparison = PullRequest::Comparison.find(
            base_commit_oid: @pull.base_sha,
            end_commit_oid: @pull.head_sha,
            pull: @pull,
            start_commit_oid: @pull.merge_base,
            viewer: @user,
          )

          actual_payload = PullRequests::PageData::Files::Toolbar::Loader.load(
            cap_filter: nil,
            comparison: pull_comparison,
            current_user: nil,
            end_commit_oid: @pull.head_sha,
            pull_request: @pull,
            user_session: @user_session
          )
          assert_equal expected_payload, actual_payload.serialize
        end
      end
    end
  end
end
