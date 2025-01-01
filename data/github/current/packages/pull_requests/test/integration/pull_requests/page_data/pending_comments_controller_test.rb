# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequests::PageData::PendingCommentsControllerTest < GitHub::IntegrationTestCase
  include ResiliencyHelpers

  fixtures do
    @user = create(:user, login: "wiseguy")
    @rando = create(:user)

    @repository = create(:private_repository, admin: @user, from_example: :review_comment_fork)
    create(:collaborator, collaborator: @user, repository: @repository)

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

    @api_route = "#{@pull.url}/page_data/pending_review"
  end

  test "returns 200 and the pending comment when user has read access to the repository and pull reuqest" do
    review = PullRequestReview.create(
      user: @user,
      pull_request: @pull,
      state: :pending,
      head_sha: @pull.head_sha,
    )

    comment = create(:pull_request_review_comment,
      pull_request: @pull,
      user: @user,
      body: "hiya",
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 26,
      pull_request_review: review,
    )

    @pull.reload
    as @user
    get @api_route, xhr: true

    assert_response_success
    json = JSON.parse(response.body)

    assert_equal json["id"], review.id
    # The actual shape of the data is tested in the loader/payload tests
    assert_equal json["comments"].length, 1
  end

  test "returns 404 for user without read access to the repository" do
    as @rando
    get @api_route

    assert_response_not_found
  end

  test "returns 404 if pull request is not found" do
    non_existent_pr_number = "0" * 40

    as @user
    get  "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{non_existent_pr_number}/page_data/viewed_files_count", xhr: true

    assert_response_not_found
  end

  test "returns 406 if not an xhr request" do
    as @pull.user
    get @api_route, xhr: false

    assert_response :not_acceptable
  end
end
