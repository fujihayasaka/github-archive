# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadCheckSuitePayloadTest < GitHub::TestCase
  include PushTestHelper

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create :user, login: "octocat"
    @org  = create :organization, admin: @user, login: "github"
    @repo = create :repository, owner: @user, name: "Hello-World", from_example: :rebase_pull_request
    @github_app = create(:integration, :with_active_hook, default_permissions: { "checks" => :write },
      default_events: %w(check_suite), name: "Super-Duper", owner: @org)
    @installation = make_integration_installation(integration: @github_app, target: @user)

    # Use existing git repo `rebase_pull_request`
    # Which lives in test/fixtures/git/examples/rebase_pull_request.git

    # Create a PR between master and [existing] contrib branches on that repo.
    @pull = create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "contrib",
      user: @user,
    )

    # Make a new commit on contrib branch,
    # so that there is a diff to compare after a Push of that commit
    @before = @repo.heads.find("contrib").target_oid
    metadata = { message: "blah", committer: @user }
    commit = @repo.heads.find("contrib").append_commit(metadata, @user) do |files|
      files.add("foo", "dsfdsfsdfsd")
    end
    @sha = commit.oid

    # Create a Push for the fresh commit(s) on the feature branch.
    perform_enqueued_jobs(only: [CreateCheckSuitesJob]) do
      trigger_push_event(
        @repo.shard_path,
        @user.login,
        [["refs/heads/contrib", @before, @sha]],
        Time.now,
        perform_hydro_push_jobs: [HydroRepositoriesOnPushJob]
      )
    end

    @push = @repo.pushes.first
    @check_suite = CheckSuite.where(push_id: @push.id).last


    event = Hook::Event::CheckSuiteEvent.new(action: :created, check_suite_id: T.must(@check_suite).id)
    @payload = Hook::Payload::CheckSuitePayload.new event
  end

  test "v3" do
    v3          = @payload.to_hash
    check_suite = v3[:check_suite]
    path        = "/repos/octocat/Hello-World/check-suites/#{@check_suite.id}"

    assert_equal :created, v3[:action]

    assert_equal "contrib", check_suite[:head_branch]
    assert_equal @sha, check_suite[:head_sha]

    assert_equal @check_suite.status, check_suite[:status]
    assert_nil check_suite.fetch(:conclusion) # status is queued, and therefore the conlcusion should be nil

    assert_equal @before, check_suite[:before]
    assert_equal @github_app.id, check_suite[:app][:id]
    assert check_suite[:url].end_with?(path), "#{check_suite[:url]} doesn't end with #{path}"
    assert_equal @pull.id, check_suite[:pull_requests].first[:id]
    refute check_suite.key?(:repository), "Repository key should not be included in CheckSuite payloads"

    assert_equal [:action, :actions_meta, :check_suite, :repository, :sender], v3.keys.sort, "No launch data should be in the payload"

    assert_equal true, check_suite[:rerequestable]
    assert_equal true, check_suite[:runs_rerequestable]
  end

  test "includes a conclusion when completed" do
    @check_suite.destroy # make sure there are no collisions with current check_suite
    check_suite = create(
      :check_suite,
      :success,
      repository: @repo,
      head_sha: @sha,
      head_branch: nil,
      github_app: @github_app
    )

    event = Hook::Event::CheckSuiteEvent.new(action: :completed, check_suite_id: check_suite.id)
    payload = Hook::Payload::CheckSuitePayload.new event
    v3 = payload.to_hash
    check_suite_payload = v3[:check_suite]

    assert_equal check_suite.conclusion, check_suite_payload[:conclusion]
  end

  test "includes pull requests when a head_branch is known" do
    after      = @repo.refs["contrib"].commit
    middle     = @repo.commits.find(after.first_parent_oid)
    middle_sha = middle.oid

    check_suite = create(:check_suite, repository: @repo, head_sha: middle_sha,
      head_branch: "contrib",
      github_app: @github_app)

    event       = Hook::Event::CheckSuiteEvent.new(action: :requested, check_suite_id: check_suite.id)
    payload     = Hook::Payload::CheckSuitePayload.new event
    v3          = payload.to_hash
    check_suite = v3[:check_suite]

    refute_empty check_suite[:pull_requests]
    assert_equal @pull.id, check_suite[:pull_requests].first[:id]
  end

  test "does not include pull requests when a head_branch is not known" do
    after      = @repo.refs["contrib"].commit
    middle     = @repo.commits.find(after.first_parent_oid)
    middle_sha = middle.oid

    check_suite = create(:check_suite, repository: @repo, head_sha: middle_sha,
      head_branch: nil,
      github_app: @github_app)

    event       = Hook::Event::CheckSuiteEvent.new(action: :requested, check_suite_id: check_suite.id)
    payload     = Hook::Payload::CheckSuitePayload.new event
    v3          = payload.to_hash
    check_suite = v3[:check_suite]

    assert_empty check_suite[:pull_requests]
  end
end
