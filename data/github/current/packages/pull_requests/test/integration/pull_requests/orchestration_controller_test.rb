# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequests::OrchestrationControllerTest < GitHub::IntegrationTestCase
  fixtures do
    @repo = create(:repository, from_example: :pull_request_source)
    @pull = create(:pull_request, :with_mergeable_head, repository: @repo)
  end

  test "returns error message" do
    user_without_permissions = create(:user)
    result = perform_enqueued_jobs(only: [PullRequestOrchestrationJob]) do
      PullRequests::UpdateBranch.execute(pull_request: @pull, user: user_without_permissions, update_method: "merge", expected_head_oid: @pull.head_sha)
    end

    as @pull.user
    get "/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/orchestration/#{result.orchestration.id}"

    assert_response 200

    json_response = JSON.parse(response.body)
    assert_equal "skipped", json_response["orchestration"]["state"]
    assert_equal 1, json_response["orchestration"]["attempts"]
    assert_equal "You don't have permission write to the base repository.", json_response["orchestration"]["error_message"]
  end

  test "returns state while job is running" do
    result = PullRequests::UpdateBranch.execute(pull_request: @pull, user: @pull.user, update_method: "merge", expected_head_oid: @pull.head_sha)
    as @pull.user
    get "/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/orchestration/#{result.orchestration.id}"

    assert_response 202

    json_response = JSON.parse(response.body)
    assert_equal "running", json_response["orchestration"]["state"]
  end
end
