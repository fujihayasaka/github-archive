# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequests::PageData::CodeButtonControllerTest < GitHub::IntegrationTestCase
  fixtures do
    @user = create(:user)
    repo = create(:repository, admin: @user, from_example: :review_comment_fork)
    create(:collaborator, collaborator: @user, repository: repo)
    assert repo.member?(@user)

    @pull = create(:pull_request,
      repository: repo,
      base_repository: repo,
      base_user: @user,
      base_ref: "master",
      head_repository: repo,
      head_user: @user,
      head_ref: "topic",
      user: @user
    )

    @new_codespace_path = "/codespaces/new?hide_repo_select=true&ref=#{@pull.head_ref}&repo=#{repo.id}"

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  test "responds with success for logged in user" do
    # Codespace access differs depending on test mode (dotcom vs MT vs EMU), so rather than jump through
    # hoops to set up the user, repo, org, etc. data correctly for each mode, we're stubbing it out.
    has_access_to_codespaces = !GitHub.enterprise?
    Codespaces::MenuVisibility.any_instance.stubs(:has_access_to_codespaces?).returns(has_access_to_codespaces)

    as @user
    get "#{@pull.url}/page_data/code_button", xhr: true
    assert_response_success

    # Spot check critical values in the response
    json = JSON.parse(response.body)

    # If logged in, current user may or may not have access to codespaces, so we're testing both paths.
    # Either way, the overall response should still be successful. Only this single JSON value will differ.
    if has_access_to_codespaces
      assert json["hasAccessToCodespaces"]
    else
      refute json["hasAccessToCodespaces"]
    end

    assert json["isLoggedIn"]
    assert json["newCodespacePath"], @new_codespace_path
  end

  test "responds with success for logged out user" do
    get "#{@pull.url}/page_data/code_button", xhr: true
    assert_response_success

    # Spot check critical values in the response
    json = JSON.parse(response.body)

    # If logged out, viewer will never have access to codespaces
    refute json["hasAccessToCodespaces"]
    refute json["isLoggedIn"]
    assert json["newCodespacePath"], @new_codespace_path
  end

  test "returns 404 if pull request is not found" do
    as @user
    get "#{@pull.url}000/page_data/code_button"

    assert_response_not_found
  end

  test "returns 406 if not an xhr request" do
    as @user
    get "#{@pull.url}/page_data/code_button"

    assert_response :not_acceptable
  end
end
