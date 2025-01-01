# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequests::PageData::MergeInstructionsControllerTest < GitHub::IntegrationTestCase
  include ResiliencyHelpers

  fixtures do
    @owner = create(:user, login: "wiseguy")
    @rando  = create(:user)
    @source = create(:repository, owner: @owner, name: "source", from_example: :pr_mergeability)

    @pull =
      create(:pull_request,
        repository: @source,
        base_repository: @source,
        base_user: @source.owner,
        base_ref: "master",
        head_repository: @source,
        head_user: @source.owner,
        head_ref: "ahead",
        user: @owner
      )
  end

  test "returns 200 for a valid request" do
    as @owner

    get "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/merge_instructions", xhr: true

    assert_response :ok
  end

  test "depends on clusters" do
    as @owner

    with_non_required_clusters_raising do
      get "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/merge_instructions", xhr: true
    end

    assert_response :ok
  end

  test "returns 404 if pull request is not found" do
    as @owner
    get "#{@pull.url}000/page_data/merge_instructions", xhr: true

    assert_response_not_found
  end

  test "returns 406 if not an xhr request" do
    as @owner

    get "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/merge_instructions"

    assert_response :not_acceptable
  end

  test "return 404 if user not logged in" do
    get "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/merge_instructions", xhr: true

    assert_response_not_found
  end
end
