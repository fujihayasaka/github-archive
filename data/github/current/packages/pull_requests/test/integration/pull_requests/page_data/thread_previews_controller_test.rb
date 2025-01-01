# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequests::PageData::ThreadPreviewsControllerTest < GitHub::IntegrationTestCase
  include ResiliencyHelpers

  fixtures do
    @user = create(:user, login: "wiseguy")
    @rando = create(:user)
    @repository = create(:private_repository, owner: @user, from_example: :review_comment_fork)
    @pull =
      create(:pull_request,
        :with_mergeable_head,
        repository: @repository,
        base_repository: @repository,
        base_user: @user,
        base_ref: "master",
        head_repository: @repository,
        head_user: @user,
        head_ref_name: "topic2",
        user: @user
      )
    @pr_review = create(:pull_request_review, pull_request: @pull, user: @user, body: "this is good")
    @pr_review_thread = create(:pull_request_review_thread, pull_request: @pull, pull_request_review: @pr_review)
    @pr_review_comment = create(:pull_request_review_comment,
      pull_request: @pull,
      user: @user,
      pull_request_review: @pr_review,
      pull_request_review_thread: @pr_review_thread
    )
    @api_route = "#{@pull.url}/page_data/thread_previews"

  end

  test "returns 200 and thread previews when user has read access to the repository and pull request" do
    UserReviewedFile.create!(
      filepath: "bar.txt",
      user: @user,
      pull_request: @pull,
      head_sha: @pull.head_sha,
    )
    @pull.reload
    as @user
    get @api_route, xhr: true

    assert_response_success
    json = JSON.parse(response.body)

    assert_equal json.count, 1

    expected_payload = [{
      "firstComment" => {
        "author" => {
          "login" => @user.display_login,
          "avatarUrl" => @user.primary_avatar_url
        },
        "authorAssociation" => TestEnv.test_with_all_emus? ? "COLLABORATOR" : "OWNER",
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
          "isPrivate" => true,
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
        "viewerCanDelete" => false,
        "viewerCanMinimize" => false,
        "viewerCanSeeMinimizeButton" => false,
        "viewerCanSeeUnminimizeButton" => false,
        "viewerCanReport" => false,
        "viewerCanReportToMaintainer" => false,
        "viewerCanUnblockFromOrg" => false,
        "viewerCanUpdate" => false,
        "viewerDidAuthor" => true,
        "viewerRelationship" => "OWNER"
      },
      "line" => 1,
      "id" => @pr_review_thread.id.to_s,
      "isOutdated" => false,
      "isResolved" => false,
      "path" => "bar.txt",
      "subject" => {
        "diffLines" => [
          {
            "html" => "@@ -0,0 +1 @@",
            "left" => nil,
            "right" => 0,
            "text" => "@@ -0,0 +1 @@",
            "type" => "HUNK"
          },
          {
            "html" => "Test",
            "left" => nil,
            "right" => 1,
            "text" => "+Test",
            "type" => "ADDITION"
          }
        ],
        "endLine" => 1,
        "endDiffSide" => "RIGHT",
        "originalEndLine" => 1,
        "originalStartLine" => nil,
        "pullRequestCommit" => {
          "commit" => {
            "abbreviatedOid" => @pull.head_sha
          }
        },
        "startDiffSide" => "RIGHT",
        "startLine" => 1
      },
      "threadPreviewComments" => []
    }]

    assert_equal expected_payload.as_json, json
  end

  test "returns 404 for user without read access to the repository" do
    as @rando
    get @api_route

    assert_response_not_found
  end

  test "returns 404 if pull request is not found" do
    non_existent_pr_number = "0" * 40

    as @user
    get  "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{non_existent_pr_number}/page_data/thread_previews", xhr: true

    assert_response_not_found
  end

  test "returns 406 if not an xhr request" do
    as @pull.user
    get @api_route, xhr: false

    assert_response :not_acceptable
  end
end
