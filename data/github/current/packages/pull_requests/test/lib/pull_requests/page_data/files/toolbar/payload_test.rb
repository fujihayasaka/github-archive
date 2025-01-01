# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module PageData::Files::Toolbar
    class PayloadTest < GitHub::TestCase
      fixtures do
        @user = create(:user)
        @user_session = create(:authentication_record, user: @user).user_session
        repo = create(:repository, admin: @user, from_example: :pull_request_history)
        create(:collaborator, collaborator: @user, repository: repo)
        assert repo.member?(@user)
        enable_feature_flag(:copilot_workspace)

        @pull = create(:pull_request,
          base_ref: repo.default_branch,
          base_repository: repo,
          base_user: @user,
          head_ref_name: "topic",
          head_repository: repo,
          head_user: @user,
          repository: repo,
          user: @user,
        )
      end

      test "serializes the code button with Ruby conventions using to_hash" do
        Timecop.freeze do # Freeze the time to avoid flakiness of the generated alive channel
          @expected_payload = {
            "annotations" => [],
            "copilotAccessAllowed" => true,
            "currentUserLogin" => @user.display_login,
            "isFileTreeExpanded" => true,
            "pullRequest" => {
              "aliveChannel" => GitHub::WebSocket::Channels.signed_pull_request(@pull),
              "author" => {
                "login" => @user.display_login,
              },
              "comparison" => {
                "baseOid" => @pull.historical_comparison.async_base_oid.sync,
                "headOid" => @pull.historical_comparison.async_head_oid.sync
              },
              "id" => @pull.global_relay_id,
              "pathName" => @pull.permalink(include_host: false),
              "repository" => {
                "id" => @pull.repository.id,
                "viewerPermission" => "write",
              },
              "state" => "OPEN",
              "viewerCanLeaveNonCommentReviews" => false,
              "viewerHasViolatedPushPolicy" => false
            },
            "shouldShowViewedFilesCount" => true,
            "threadPreviews" => [],
            "totalFilesCount" => 1,
            "viewedFilesCount" => 0,
            "viewerPendingReview" => {
              "id" => nil,
              "comments" => [],
            },
            "viewSettings" => {
              "hideWhitespace" => false,
              "lineSpacing" => "relaxed",
              "splitPreference" => "unified",
              "commentsPreference" => "visible",
            },
          }

          pull_comparison = PullRequest::Comparison.find(
            base_commit_oid: @pull.base_sha,
            end_commit_oid: @pull.head_sha,
            pull: @pull,
            start_commit_oid: @pull.merge_base,
            viewer: @user,
          )

          data = PullRequests::PageData::Files::Toolbar::Loader.load(
            cap_filter: nil,
            comparison: pull_comparison,
            current_user: @user,
            end_commit_oid: @pull.head_sha,
            pull_request: @pull,
            user_session: nil,
          )

          assert_no_queries do
            actual_payload = PullRequests::PageData::Files::Toolbar::Payload.call(data)
            assert_equal @expected_payload.as_json, actual_payload.as_json
          end
        end
      end
    end
  end
end
