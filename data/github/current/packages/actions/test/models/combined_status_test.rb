# typed: true
# frozen_string_literal: true

require "test_helper"

class CombinedStatusTest < GitHub::TestCase
  fixtures do
    @owner        = create :user, plan: "medium"
    @repo         = create :repository, owner: @owner
    @github_app   = create :integration, default_permissions: { "checks" => :write }, name: "Super-Duper", owner: @owner, url: "http://super-duper.com"

    make_trusted_oauth_apps_owner
    @launch_app   = create :launch_integration

    @installation = make_integration_installation integration: @github_app, repository: @repo

    reset_repo_root
    example_repo :simple, @repo # rubocop:disable GitHub/UseFromExampleInRepositoryFactory

    commit = @repo.refs["master"].commit
    @sha1  = commit.first_parent_oid
    @sha2  = commit.oid

    @check_suite = create :check_suite, repository: @repo, creator: @owner, github_app: @github_app, head_branch: "master", head_sha: @sha1
  end

  test "is accessible for a repo via #combined_status" do
    assert_equal "pending", @repo.combined_status(@sha1).state
  end

  test "creates a combined status from statuses loaded on the fly" do
    create :status, sha: @sha1, state: "pending", creator: @owner, repository: @repo, context: "context 1"
    create :status, sha: @sha1, state: "success", creator: @owner, repository: @repo, context: "context 2"
    create :status, sha: @sha1, state: "failure", creator: @owner, repository: @repo, context: "context 1"

    combined_status = CombinedStatus.new(@repo, @sha1, check_runs: [])
    assert_equal "failure", combined_status.state
    assert_equal 2, combined_status.count
  end

  test "creates a combined status from latest check runs loaded on the fly ignoring hidden check suites" do
    hidden_check_suite = create(:check_suite, event: "schedule", head_sha: @check_suite.head_sha, repository: @check_suite.repository, workflow_file_path: ".github/workflows/main.yml")

    create :check_run, check_suite: @check_suite, name: "ci", status: "in_progress"
    create :check_run, check_suite: @check_suite, name: "ci", status: "in_progress"
    create :check_run, check_suite: @check_suite, name: "coverage", status: "queued"
    create :check_run, check_suite: hidden_check_suite, name: "scheduled", status: "in_progress"

    combined_status = CombinedStatus.new(@repo, @sha1, statuses: [])
    assert_equal "pending", combined_status.state
    assert_equal 2, combined_status.count
  end

  test "creates a combined status from latest check runs loaded on the fly ignoring hidden check suites and showing only the latest check suite for an event" do
    GitHub.instance_variable_set("@actions_enabled", true) # work around to enable launch integration
    newer_check_suite = create(:check_suite_for_actions_app, repository: @repo, creator: @owner, github_app: @launch_app, head_branch: "master", head_sha: @sha1)
    older_check_suite = create(:check_suite_for_actions_app, event: "pull_request", head_sha: newer_check_suite.head_sha, github_app: @launch_app, repository: newer_check_suite.repository, workflow_file_path: ".github/workflows/main.yml")
    create :check_run, check_suite: older_check_suite, name: "ci", status: "completed", conclusion: "success"
    newer_check_suite.update(event: "pull_request", workflow_file_path: ".github/workflows/main.yml")
    create :check_run, check_suite: newer_check_suite, name: "coverage", status: "in_progress"

    check_suite_different_workflow = create(:check_suite, event: "pull_request", head_sha: newer_check_suite.head_sha, github_app: @launch_app, repository: newer_check_suite.repository, workflow_file_path: ".github/workflows/pull_request.yml")
    create :check_run, check_suite: check_suite_different_workflow, name: "coverage", status: "completed", conclusion: "success"

    combined_status = CombinedStatus.new(@repo, @sha1, statuses: [])
    assert_equal "success", combined_status.state
    assert_equal 2, combined_status.count
    GitHub.instance_variable_set("@actions_enabled", false)
  end

  test "creates a combined status from preloaded statuses" do
    run1 = create :check_run, check_suite: @check_suite, name: "ci", status: "in_progress"
    run2 = create :check_run, check_suite: @check_suite, name: "coverage", status: "queued"

    # This status is for the same sha and name, but it is not being taken into account, since we're injecting the check runs.
    # Had it been taken into account, the :state would be 'failure'.
    _ = create :check_run, name: "complexity", check_suite: @check_suite, status: "completed", completed_at: Time.now, conclusion: "failure"

    combined_status = CombinedStatus.new(@repo, @sha1, statuses: [], check_runs: [run1, run2])
    assert_equal "pending", combined_status.state
    assert_equal 2, combined_status.count
  end

  test "creates a combined status from preloaded check_runs" do
    s1 = create :status, sha: @sha1, state: "pending", creator: @owner, repository: @repo, context: "context 1"
    s2 = create :status, sha: @sha1, state: "success", creator: @owner, repository: @repo, context: "context 2"

    # This status is for the same sha and context, but it is not being taken into account,
    # since we're injecting the statuses.
    # Had it been taken into account, the :state would be 'failure'.
    _ = create :status, sha: @sha1, state: "failure", creator: @owner, repository: @repo, context: "context 1"

    combined_status = CombinedStatus.new(@repo, @sha1, statuses: [s1, s2], check_runs: [])
    assert_equal "pending", combined_status.state
    assert_equal 2, combined_status.count
  end

  test "only cares about the given sha1 when loading statuses on the fly" do
    create :status, sha: @sha1, state: "success", creator: @owner, repository: @repo, context: "context 1"
    create :status, sha: @sha2, state: "pending", creator: @owner, repository: @repo, context: "context 1"
    create :status, sha: @sha1, state: "success", creator: @owner, repository: @repo, context: "context 2"

    assert_equal "success", CombinedStatus.new(@repo, @sha1, check_runs: []).state
  end

  test "only cares about the given sha1 when loading check runs on the fly" do
    create :check_run, check_suite: @check_suite, name: "ci", status: "in_progress"
    create :check_run, check_suite: @check_suite, name: "coverage", status: "queued"

    suite2 = create :check_suite, repository: @repo, creator: @owner, github_app: @github_app, head_branch: "master", head_sha: @sha2
    create :check_run, check_suite: suite2, name: "complexity", status: "completed", completed_at: Time.now, conclusion: "failure"

    assert_equal "pending", CombinedStatus.new(@repo, @sha1).state
  end

  test "ignores hidden check suites when calculating the state" do
    hidden_check_suite = create(:check_suite, event: "schedule", head_sha: @sha1)

    create :check_run, :success, check_suite: @check_suite, name: "ci"
    create :check_run, :failure, check_suite: hidden_check_suite, name: "coverage"

    assert_equal "success", CombinedStatus.new(@repo, @sha1).state
  end

  test "#short_text returns text that was provided to constructor" do
    expected_short_text = "this is a short text"
    combined_status = CombinedStatus.new(@repo, @sha1, short_text: expected_short_text)

    assert_equal expected_short_text, combined_status.short_text
  end

  test "#short_text returns text based on check run status" do
    create :check_run, check_suite: @check_suite, name: "ci", status: "in_progress"
    create :check_run, check_suite: @check_suite, name: "coverage", status: "queued"
    combined_status = CombinedStatus.new(@repo, @sha1)

    assert_equal "0 / 2 checks OK", combined_status.short_text
  end

  test "#prefill fills creators in statuses, but not check runs" do
    status1 = create :status, repository: @repo
    status2 = create :status, repository: @repo, creator: status1.creator
    status3 = create :status, repository: @repo

    status1 = Status.where(repository_id: @repo.id).find(status1.id)
    status2 = Status.where(repository_id: @repo.id).find(status2.id)
    status3 = Status.where(repository_id: @repo.id).find(status3.id)

    run1 = create :check_run, check_suite: @check_suite, name: "ci", status: "in_progress"
    run2 = create :check_run, check_suite: @check_suite, name: "coverage", status: "queued"

    run1 = CheckRun.find(run1.id)
    run2 = CheckRun.find(run2.id)

    refute status1.association(:creator).loaded?
    refute status2.association(:creator).loaded?
    refute status3.association(:creator).loaded?
    refute run1.association(:creator).loaded?
    refute run1.association(:creator).loaded?

    status = CombinedStatus.new(@repo, @sha1, statuses: [status1, status2, status3], check_runs: [run1, run2])
    status.prefill

    assert status1.association(:creator).loaded?
    assert status2.association(:creator).loaded?
    assert status3.association(:creator).loaded?
    refute run1.association(:creator).loaded?
    refute run1.association(:creator).loaded?
  end

  test "#prefill fills oauth applications on statuses but not check runs (which don't have them)" do
    status1 = create :status, repository: @repo, oauth_application: create(:oauth_application)
    status2 = create :status, repository: @repo, oauth_application: status1.oauth_application
    status3 = create :status, repository: @repo, oauth_application: create(:oauth_application)
    status4 = create :status, repository: @repo

    status1 = Status.where(repository_id: @repo.id).find(status1.id)
    status2 = Status.where(repository_id: @repo.id).find(status2.id)
    status3 = Status.where(repository_id: @repo.id).find(status3.id)
    status4 = Status.where(repository_id: @repo.id).find(status4.id)

    run1 = create :check_run, check_suite: @check_suite, name: "ci", status: "in_progress"
    run2 = create :check_run, check_suite: @check_suite, name: "coverage", status: "queued"

    run1 = CheckRun.find(run1.id)
    run2 = CheckRun.find(run2.id)

    refute status1.association(:oauth_application).loaded?
    refute status2.association(:oauth_application).loaded?
    refute status3.association(:oauth_application).loaded?
    refute status4.association(:oauth_application).loaded?

    refute run1.association(:creator).loaded?
    refute run1.association(:creator).loaded?

    status = CombinedStatus.new(@repo, @sha1, statuses: [status1, status2, status3], check_runs: [run1, run2])
    status.prefill

    assert status1.association(:oauth_application).loaded?
    assert status2.association(:oauth_application).loaded?
    assert status3.association(:oauth_application).loaded?
    # This status doesn't have an OauthApplication.
    refute status4.association(:oauth_application).loaded?

    assert T.must(status1.oauth_application).association(:user).loaded?
    assert T.must(status2.oauth_application).association(:user).loaded?
    assert T.must(status3.oauth_application).association(:user).loaded?
    refute run1.association(:creator).loaded?
    refute run1.association(:creator).loaded?
  end

  test "knows how many contexts there are" do
    statuses = [
      Status.new(state: "success"),
      Status.new(state: "pending"),
    ]
    check_runs = [
      CheckRun.new(conclusion: "success"),
    ]
    assert_equal 3, CombinedStatus.new(Repository.new, "1" * 40, statuses: statuses, check_runs: check_runs).count
  end

  test "returns latest check runs and statuses with #statuses" do
    s1   = Status.new(id: 1, state: "success")
    s2   = Status.new(id: 2, state: "pending")
    run1 = CheckRun.new(id: 3, conclusion: "success")
    assert_equal [s1, s2, run1].map(&:id), CombinedStatus.new(Repository.new, "1" * 40, statuses: [s1, s2], check_runs: [run1]).statuses.map(&:id)
  end

  test "responds to #paginate" do
    s1     = Status.new(id: 1, state: "success")
    s2     = Status.new(id: 2, state: "success")
    s3     = Status.new(id: 3, state: "success")
    run1   = CheckRun.new(id: 4, status: "in_progress")
    run2   = CheckRun.new(id: 5, conclusion: "success")
    run3   = CheckRun.new(id: 6, conclusion: "success")
    status = CombinedStatus.new(Repository.new, "1" * 40, statuses: [s1, s2, s3], check_runs: [run1, run2, run3])

    retval = status.paginate(per_page: 2, page: 2)
    assert_equal status, retval
    assert_equal [s3.id, run1.id], status.statuses.map(&:id)
    assert_equal 3, status.total_pages

    status.paginate(per_page: 1, page: 2)
    assert_equal [s2.id], status.statuses.map(&:id)
    assert_equal 6, status.total_pages

    status.paginate(per_page: 2, page: 5)
    assert_equal [], status.statuses.map(&:id)
    assert_equal 3, status.total_pages
  end

  test "any? is true if there are any statuses" do
    statuses = [
      Status.new(state: "success"),
    ]
    status = CombinedStatus.new(Repository.new, "1" * 40, statuses: statuses, check_runs: [])
    assert status.any?
  end

  test "any? is true if there are any check runs" do
    runs = [
      CheckRun.new(status: "in_progress"),
    ]
    status = CombinedStatus.new(Repository.new, "1" * 40, statuses: [], check_runs: runs)
    assert status.any?
  end

  test "any? is false if there are no statuses or check runs" do
    status = CombinedStatus.new(Repository.new, "1" * 40, statuses: [], check_runs: [])
    refute status.any?
  end

  test "no single status when empty" do
    status = CombinedStatus.new(Repository.new, "1" * 40, statuses: [], check_runs: [])
    assert_nil status.single_status
  end

  test "single status when one context reported" do
    statuses = [
      Status.new(state: "pending"),
    ]

    status = CombinedStatus.new(Repository.new, "1" * 40, statuses: statuses, check_runs: [])
    assert_equal statuses.first, status.single_status
  end

  test "single status when one check run reported" do
    runs = [
      CheckRun.new(id: 1, status: "queued"),
    ]

    status = CombinedStatus.new(Repository.new, "1" * 40, statuses: [], check_runs: runs)
    assert_equal runs.first.id, status.single_status.id
  end

  test "no single status when multiple contexts reported" do
    statuses = [
      Status.new(state: "pending"),
      Status.new(state: "success"),
    ]

    status = CombinedStatus.new(Repository.new, "1" * 40, statuses: statuses, check_runs: [])
    assert_nil status.single_status
  end

  test "no single status when one contexts and one check run reported" do
    statuses = [
      Status.new(state: "pending"),
    ]
    runs = [
      CheckRun.new(status: "queued"),
    ]

    status = CombinedStatus.new(Repository.new, "1" * 40, statuses: statuses, check_runs: runs)
    assert_nil status.single_status
  end

  test "cache key" do
    statuses = [
      Status.new(id: 1, created_at: Time.now - 10),
    ]
    runs = [
      CheckRun.new(id: 2, created_at: Time.now),
    ]

    # First create one with no check runs
    status = CombinedStatus.new(Repository.new(id: 0), "1" * 40, statuses: statuses, check_runs: [])
    assert_kind_of String, status.cache_key
    old_cache_key = status.cache_key

    # Then pass the check run in
    status = CombinedStatus.new(Repository.new(id: 0), "1" * 40, statuses: statuses, check_runs: runs)
    assert_kind_of String, status.cache_key

    refute_equal old_cache_key, status.cache_key
  end
end
