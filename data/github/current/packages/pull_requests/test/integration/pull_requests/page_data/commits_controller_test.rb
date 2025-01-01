# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequests::PageData::CommitsControllerTest < GitHub::IntegrationTestCase
  include ResiliencyHelpers

  fixtures do
    @owner = create(:user, login: "skalnik")
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

    # You can get into a state like this by force-pushing, but for ease of
    # setup, let's skip validations enforcing some commits when creating a PR
    branch = "empty-branch"
    commit_oid = @source.ref_to_sha(@source.default_branch)
    @source.heads.create(branch, commit_oid, @source.owner, reflog_data: {})
    issue = create(:issue, user: @owner, repository: @source, title: "The higher the ISO the more sensitive the film")
    @no_commit_pr = PullRequest.build(
      repository: @source,
      base_repository: @source,
      base_user: @source.owner,
      base_ref: "master",
      head_repository: @source,
      head_user: @source.owner,
      head_ref: branch,
      issue: issue,
      user: @owner)
    @no_commit_pr.save(validate: false)
  end

  test "returns 200 and actual commit content" do
    as @pull.user
    get "#{@pull.url}/page_data/commits", xhr: true

    assert_response_success
    json = JSON.parse(response.body)

    assert json["commitGroups"].present?
    assert_equal json["commitGroups"].size, 2
    assert_equal json["commitGroups"][0]["commits"][0]["oid"], @pull.changed_commits.first.oid
  end

  test "returns 200 even if no commits exist" do
    as @source.owner
    get "#{@no_commit_pr.url}/page_data/commits", xhr: true

    assert_response_success
    json = JSON.parse(response.body)

    assert_equal json["commitGroups"], []
  end

  test "returns 404 for user without read access to the repository" do
    as @rando
    get "#{@pull.url}/page_data/commits"

    assert_response_not_found
  end

  test "returns 404 if pull request is not found" do
    as @owner
    get "#{@pull.url}000/page_data/commits"

    assert_response_not_found
  end

  test "degrades gracefully when GitRPC request times out" do
    PullRequests::PageData::CommitsPayload.any_instance.stubs(:build_grouped_commits_payload).raises(GitRPC::Timeout.new)

    as @pull.user
    get "#{@pull.url}/page_data/commits", xhr: true

    assert_response_success
    json = JSON.parse(response.body)

    assert_equal json["commitGroups"], []
    assert_equal json["timeOutMessage"], "git log master"
  end

  test "returns 406 if not an xhr request" do
    as @pull.user
    get "#{@pull.url}/page_data/commits"

    assert_response :not_acceptable
  end
end
