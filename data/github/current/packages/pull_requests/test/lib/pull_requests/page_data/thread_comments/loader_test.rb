# typed: true
# frozen_string_literal: true

require "test_helper"
require "json"

module PullRequests
  module PageData::ThreadComments
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
          "author_association" => "COLLABORATOR",
          "author_avatar_url" => @pr_review_comment.user.primary_avatar_url,
          "body_html" => @pr_review_comment.body_html,
          "comment" => @pr_review_comment,
          "current_diff_resource_path" => @pr_review_comment.async_current_diff_path_uri.sync.to_s,
          "outdated" => false,
          "reference_author_login" => @pull.user.display_login,
          "subject_type" => "line",
          "viewer_can_block_from_org" => false,
          "viewer_can_delete" => true,
          "viewer_can_minimize" => false,
          "viewer_can_see_minimize_button" => false,
          "viewer_can_see_unminimize_button" => false,
          "viewer_can_report" => TestEnv.enterprise? || TestEnv.test_with_all_emus? ? false : true,
          "viewer_can_report_to_maintainer" => false,
          "viewer_can_unblock_from_org" => false,
          "viewer_can_update" => true,
          "viewer_did_author" => true,
          "viewer_relationship" => "COLLABORATOR",
        }]

        actual_payload = PullRequests::PageData::ThreadComments::Loader.load(thread: @pr_review_thread, current_user: @user, max_comments: nil)
        assert_equal expected_payload, actual_payload.map { |c| c.serialize }
      end

      test "returns expected payload for logged out user" do
        expected_payload = [{
          "author_association" => "COLLABORATOR",
          "author_avatar_url" => @pr_review_comment.user.primary_avatar_url,
          "body_html" => @pr_review_comment.body_html,
          "comment" => @pr_review_comment,
          "current_diff_resource_path" => @pr_review_comment.async_current_diff_path_uri.sync.to_s,
          "outdated" => false,
          "reference_author_login" => @pull.user.display_login,
          "subject_type" => "line",
          "viewer_can_block_from_org" => false,
          "viewer_can_delete" => false,
          "viewer_can_minimize" => false,
          "viewer_can_see_minimize_button" => false,
          "viewer_can_see_unminimize_button" => false,
          "viewer_can_report" => false,
          "viewer_can_report_to_maintainer" => false,
          "viewer_can_unblock_from_org" => false,
          "viewer_can_update" => false,
          "viewer_did_author" => false,
          "viewer_relationship" => "NONE",
        }]

        actual_payload = PullRequests::PageData::ThreadComments::Loader.load(thread: @pr_review_thread, current_user: @nil, max_comments: nil)
        assert_equal expected_payload, actual_payload.map { |c| c.serialize }
      end
    end
  end
end
