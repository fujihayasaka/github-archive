# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module PageData::ThreadComments
    class PayloadTest < GitHub::TestCase
      fixtures do
        @user = create(:user)
        repo = create(:repository, admin: @user, from_example: :pull_request_history)
        create(:collaborator, collaborator: @user, repository: repo)
        assert repo.member?(@user)

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

        @pr_review = create(:pull_request_review, pull_request: @pull, user: @user, body: "this is good")
        @pr_review_thread = create(:pull_request_review_thread, pull_request: @pull, pull_request_review: @pr_review)
        @pr_review_comment = create(:pull_request_review_comment,
          pull_request: @pull,
          user: @user,
          pull_request_review: @pr_review,
          pull_request_review_thread: @pr_review_thread
        )
      end

      test "serializes the code button with Ruby conventions using to_hash" do
        expected_payload = [{
          "author" => {
            "login" =>  @user.display_login,
            "avatarUrl" =>  @user.primary_avatar_url
          },
          "authorAssociation" => "COLLABORATOR",
          "body" => @pr_review_comment.body,
          "bodyHTML" => @pr_review_comment.body_html,
          "createdAt" => @pr_review_comment.created_at.to_s,
          "currentDiffResourcePath" => @pr_review_comment.async_current_diff_path_uri.sync.to_s,
          "databaseId" => @pr_review_comment.id,
          "id" => @pr_review_comment.global_relay_id,
          "isHidden" => false,
          "lastUserContentEdit" => nil,
          "outdated" => false,
          "publishedAt" => nil,
          "reference" =>
            { "number" => @pull.number,
              "text" => nil,
              "author" => { login: @pull.user.display_login }
            },
          "repository" =>
            { "id" => @pull.repository.id.to_s,
            "isPrivate" => TestEnv.test_with_all_emus? ? true : false,
            "name" => @pull.repository.name,
            "owner" =>
              { "id" => @pull.repository.owner.id.to_s,
              "login" => @pull.repository.owner.display_login,
              "url" => @pull.repository.owner.async_url.to_s } },
          "stafftoolsUrl" => nil,
          "state" => "pending",
          "subjectType" => "line",
          "url" =>
            "#{GitHub.url}/#{@pull.repository.owner.display_login}/#{@pull.repository.name}/pull/#{@pull.number}#discussion_r#{@pr_review_comment.id}",
          "viewerCanBlockFromOrg" => false,
          "viewerCanDelete" => true,
          "viewerCanMinimize" => false,
          "viewerCanSeeMinimizeButton" => false,
          "viewerCanSeeUnminimizeButton" => false,
          "viewerCanReport" => TestEnv.enterprise? || TestEnv.test_with_all_emus? ? false : true,
          "viewerCanReportToMaintainer" => false,
          "viewerCanUnblockFromOrg" => false,
          "viewerCanUpdate" => true,
          "viewerDidAuthor" => true,
          "viewerRelationship" => "COLLABORATOR",
        }]

        data = PullRequests::PageData::ThreadComments::Loader.load(current_user: @user, thread: @pr_review_thread, max_comments: nil)

        assert_no_queries do
          actual_payload = PullRequests::PageData::ThreadComments::Payload.call(data)
          assert_equal expected_payload.as_json, actual_payload.as_json
        end
      end
    end
  end
end
