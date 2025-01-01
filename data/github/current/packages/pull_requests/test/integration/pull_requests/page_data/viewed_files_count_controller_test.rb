# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequests::PageData::ViewedFilesCountControllerTest < GitHub::IntegrationTestCase
  include ResiliencyHelpers

  fixtures do
    @user = create(:user, login: "wiseguy")
    @rando = create(:user)
    @respository = create(:private_repository, owner: @user, from_example: :review_comment_fork)
    @pull =
      create(:pull_request,
        :with_mergeable_head,
        repository: @respository,
        base_repository: @respository,
        base_user: @user,
        base_ref: "master",
        head_repository: @respository,
        head_user: @user,
        head_ref_name: "topic2",
        user: @user
      )
    @api_route = "#{@pull.url}/page_data/viewed_files_count"
  end

  test "returns 200 and viewedFilesCount when user has read access to the repository and pull reuqest" do
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

    assert_equal json["viewedFilesCount"], 1
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
