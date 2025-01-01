# typed: true
# frozen_string_literal: true

require "test_helper"
require "json"

module PullRequests
  module PageData::ThreadPreviews
    class LoaderTest < GitHub::TestCase
      fixtures do
        @user = create(:user)
        @repository = create(:repository, admin: @user, from_example: :review_comment_fork)
        create(:collaborator, collaborator: @user, repository: @repository)
        assert @repository.member?(@user)

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

        @pr_review = create(:pull_request_review, pull_request: @pull, user: @user, body: "this is good")
        @pr_review_thread = create(:pull_request_review_thread, pull_request: @pull, pull_request_review: @pr_review)
        @pr_review_comment = create(:pull_request_review_comment,
          pull_request: @pull,
          user: @user,
          pull_request_review: @pr_review,
          pull_request_review_thread: @pr_review_thread
        )
      end

      test "returns expected payload for logged in user" do
        # Codespace access differs depending on test mode (dotcom vs MT vs EMU), so rather than jump through
        # hoops to set up the user, repo, org, etc. data correctly for each mode, we're stubbing it out.

        expected_payload = [{
          "first_comment" => [{
            "author_association" => "COLLABORATOR",
            "author_avatar_url" => @pr_review_comment.user.primary_avatar_url,
            "body_html" => @pr_review_comment.body_html,
            "comment" => @pr_review_comment,
            "current_diff_resource_path" => @pr_review_comment.async_current_diff_path_uri.sync.to_s,
            "outdated" => false,
            "reference_author_login" => @pull.user.display_login,
            "subject_type" => "line",
            "url" => @pr_review_comment.url,
            "viewer_can_block_from_org" => false,
            "viewer_can_delete" => false,
            "viewer_can_minimize" => false,
            "viewer_can_see_minimize_button" => false,
            "viewer_can_see_unminimize_button" => false,
            "viewer_can_report" => false,
            "viewer_can_report_to_maintainer" => false,
            "viewer_can_unblock_from_org" => false,
            "viewer_can_update" => false,
            "viewer_did_author" => true,
            "viewer_relationship" => "COLLABORATOR",
          }],
          "line" => 1,
          "id" => @pr_review_thread.id.to_s,
          "is_outdated" => false,
          "is_resolved" => false,
          "path" => "bar.txt",
          "subject" => {
            "diff_lines" => [
              {
                type: :hunk,
                text: "@@ -0,0 +1 @@",
                html: "@@ -0,0 +1 @@",
                position: 0,
                left: nil,
                right: 0,
                no_newline_at_end: false,
                cache_code: :miss
              },
              {
                type: :addition,
                text: "+Test",
                html: "Test",
                position: 1,
                left: nil,
                right: 1,
                no_newline_at_end: false,
                cache_code: :miss
              }
            ],
            "end_line" => 1,
            "end_diff_side" => "RIGHT",
            "original_end_line" => 1,
            "pull_request_commit" => @pull.head_sha,
            "start_diff_side" => "RIGHT",
            "start_line" => 1,
          },
          "subject_type" => "line",
          "thread_comments" => [@pr_review_comment]
        }]

        actual_payload = PullRequests::PageData::ThreadPreviews::Loader.load(pull_request: @pull, current_user: @user)
        assert_equal expected_payload, actual_payload.map(&:serialize)
      end

      test "returns expected payload for logged out user" do
        expected_payload = []

        actual_payload = PullRequests::PageData::ThreadPreviews::Loader.load(pull_request: @pull, current_user: nil)
        assert_equal expected_payload, actual_payload.map(&:serialize)
      end

      test "returns expected payload for load_counts_by_path" do
        expected_payload = {
          "bar.txt" => 1
        }

        actual_payload = PullRequests::PageData::ThreadPreviews::Loader.load_counts_by_path(pull_request: @pull, current_user: @user)
        assert_equal expected_payload, actual_payload
      end
    end
  end
end
