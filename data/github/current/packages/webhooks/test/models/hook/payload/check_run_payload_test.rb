# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadCheckRunPayloadTest < GitHub::TestCase
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
      @push = push_accessor.by_repo_id_and_after(repository_id: @repo.id, after: @sha)
    end
    @check_suite = CheckSuite.where(push_id: @push.id).last


    @check_run = create(:check_run, check_suite: @check_suite, name: "xxx", display_name: "coverage", status: "completed",
      conclusion: "success", started_at: Time.now - 1.minute, completed_at: Time.now)
    event      = Hook::Event::CheckRunEvent.new(action: :created, check_run_id: @check_run.id)
    @payload   = Hook::Payload::CheckRunPayload.new event
  end

  test "v3" do
    v3  = @payload.to_hash
    run = v3[:check_run]

    assert_equal :created, v3[:action]
    assert_equal @check_run.id, run[:id]
    assert_equal @check_run.started_at, run[:started_at]
    assert_equal @check_run.completed_at, run[:completed_at]
    assert_equal @check_run.visible_name, run[:name]
    assert_equal @pull.id, run[:pull_requests].first[:id]
    assert_equal @check_run.check_suite.id, run[:check_suite][:id]
  end

  test "includes pull requests when a head_branch is known for the check_suite" do
    after      = @repo.refs["contrib"].commit
    middle     = @repo.commits.find(after.first_parent_oid)
    middle_sha = middle.oid

    check_suite = create(:check_suite, repository: @repo, head_sha: middle_sha,
      head_branch: "contrib",
      github_app: @github_app)
    check_run = create :check_run, check_suite: check_suite

    event     = Hook::Event::CheckRunEvent.new(action: :requested, check_run_id: check_run.id)
    payload   = Hook::Payload::CheckRunPayload.new event
    v3        = payload.to_hash
    check_run = v3[:check_run]

    refute_empty check_run[:check_suite][:pull_requests]
    assert_equal @pull.id, check_run[:check_suite][:pull_requests].first[:id]
  end

  test "does not include pull requests when a head_branch is not known for the check_suite" do
    after      = @repo.refs["contrib"].commit
    middle     = @repo.commits.find(after.first_parent_oid)
    middle_sha = middle.oid

    check_suite = create(:check_suite, repository: @repo, head_sha: middle_sha,
      head_branch: nil,
      github_app: @github_app)
    check_run = create :check_run, check_suite: check_suite

    event     = Hook::Event::CheckRunEvent.new(action: :requested, check_run_id: check_run.id)
    payload   = Hook::Payload::CheckRunPayload.new event
    v3        = payload.to_hash
    check_run = v3[:check_run]

    assert_empty check_run[:check_suite][:pull_requests]
  end

  test "include a requested_action when specified" do
    event     = Hook::Event::CheckRunEvent.new(action: :requested_action,
                  requested_action: { identifier: "fix_me" },
                  check_run_id: @check_run.id)
    payload   = Hook::Payload::CheckRunPayload.new event
    v3        = payload.to_hash

    assert_equal :requested_action, v3[:action]
    assert_equal @check_run.id, v3[:check_run][:id]
    assert_equal "fix_me", v3[:requested_action][:identifier]
  end
end
