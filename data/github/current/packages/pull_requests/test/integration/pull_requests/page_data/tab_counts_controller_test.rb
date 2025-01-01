# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequests::PageData::TabCountsControllerTest < GitHub::IntegrationTestCase
  include ResiliencyHelpers

  fixtures do
    @owner = create(:user, login: "wiseguy")
    @rando  = create(:user)

    @source = create(:private_repository, owner: @owner, name: "orthochromatic", from_example: :review_comment_fork)
    @issue = create(:issue, user: @owner, repository: @source, title: "Orthochromatic film is film which is not sensitive to red light")

    @pull =
      create(:pull_request,
        repository: @source,
        base_repository: @source,
        base_user: @source.owner,
        base_ref: "master",
        head_repository: @source,
        head_user: @source.owner,
        head_ref: "topic",
        issue: @issue,
        user: @source.owner
      )


    check_suite = create(:check_suite, repository: @source, head_sha: @pull.head_sha)
    create(:check_run, :success, check_suite:, display_name: "required-run")

    create(:issue_comment, issue: @pull.issue)
  end

  test "returns 200 and actual tab counts" do
    GitHub.flipper[:prx_commits].enable
    as @pull.user
    get "#{@pull.url}/page_data/tab_counts"

    assert_response_success
    json = JSON.parse(response.body)

    assert_equal json["checksCount"], 1
    assert_equal json["conversationCount"], 1
    assert_equal json["filesChangedCount"], 3
  end

  test "returns 404 for user without read access to the repository" do
    GitHub.flipper[:prx_commits].enable(@source)
    as @rando
    get "#{@pull.url}/page_data/tab_counts"

    assert_response_not_found
  end

  test "returns 404 if pull request is not found" do
    GitHub.flipper[:prx_commits].enable(@source)
    as @owner
    get "#{@pull.url}000/page_data/tab_counts"

    assert_response_not_found
  end

  test "degrades gracefully when GitRPC request errors" do
    GitHub.flipper[:prx_commits].enable
    GitHub::Diff.any_instance.stubs(:changed_files).raises(GitRPC::Error.new)

    as @pull.user
    get "#{@pull.url}/page_data/tab_counts"

    assert_response_success
    json = JSON.parse(response.body)

    assert_equal json["filesChangedCount"], 0
  end

  test "degrades gracefully when check runs count query fails" do
    GitHub.flipper[:prx_commits].enable
    PullRequest.any_instance.stubs(:latest_check_runs_count).raises(ActiveRecord::ActiveRecordError.new)

    as @pull.user
    get "#{@pull.url}/page_data/tab_counts"

    assert_response_success
    json = JSON.parse(response.body)

    assert_equal json["checksCount"], 0
  end
end
