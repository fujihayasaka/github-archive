# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestChecksDependencyTest < GitHub::TestCase
  include PushTestHelper
  include PullRequestSynchronizationTestHelpers

  fixtures do
    Spokesd.enable_spokesd

    @org         = create :organization
    @admin       = @org.admins.first
    @forker      = create(:user)
    @github_app  = create :integration, default_permissions: { "checks" => :write }
    @head_branch = "master-forward-2"

    @source = create(:repository, owner: @org, name: "source", from_example: :pull_request_source)
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :pull_request_fork)

    issue = create(:issue,
      user:       @admin,
      repository: @source,
      body:       "hey look at this",
    )

    @pull = PullRequest.new(
      repository:      @source,
      base_repository: @source,
      base_user:       @admin,
      base_ref:        "master",
      head_repository: @source,
      head_user:       @admin,
      head_ref:        @head_branch,
      issue:           issue,
      user:            @admin,
    )
    issue.pull_request = @pull
    @pull.save!

    @installation = make_integration_installation integration: @github_app, repository: @source

    perform_enqueued_jobs(only: [CreateCheckSuitesJob]) do
      @push = push_changes(repository: @source, branch_name: @head_branch, create_via_hydro_job: true).freeze
      @sha  = @push.after
    end
    @pull.reload

    make_trusted_oauth_apps_owner

    @launch_app = create(:launch_integration)
  end

  setup do
    example_repo :pull_request_source, @source
    example_repo :pull_request_fork,   @fork
    GitHub.stubs(:launch_github_app).returns(@launch_app)
  end

  context "PullRequest#matching_check_suites" do
    test "returns a check suite associated with the last Push to the head branch" do
      assert_includes @pull.matching_check_suites, CheckSuite.where(push_id: @push.id).last
    end

    test "returns a check suite associated with the given sha and the head branch" do
      push2 = nil
      push2 = push_changes(repository: @source, branch_name: @head_branch)
      @pull.reload

      assert_includes @pull.matching_check_suites(head_sha: @sha), CheckSuite.where(push_id: @push.id).last
    end

    test "returns a check suite created before the PR was opened" do
      head_branch = "master-merged-topic"
      push = T.let(nil, T.untyped)
      perform_enqueued_jobs(only: [CreateCheckSuitesJob]) do
        push = push_changes(repository: @source, branch_name: head_branch, create_via_hydro_job: true)
      end
      check_suite = CheckSuite.where(push_id: push&.id).last
      assert check_suite, "Expected a check_suite to be created after the Push"

      issue = create(:issue,
        user:       @admin,
        repository: @source,
        body:       "hey look at this",
      )

      pull = PullRequest.new(
        repository:      @source,
        base_repository: @source,
        base_user:       @admin,
        base_ref:        "master",
        head_repository: @source,
        head_user:       @admin,
        head_ref:        head_branch,
        issue:           issue,
        user:            @admin,
      )
      issue.pull_request = pull
      pull.save!

      assert_includes pull.matching_check_suites(head_sha: push&.after), check_suite
    end

    test "does not return a check suite on a forked repo, for a PR on the source repo" do
      make_integration_installation integration: @github_app, repository: @fork
      @head_branch = "topic"

      issue = create(:issue,
        user:       @forker,
        repository: @source,
        body:       "hey look at this",
      )
      @pull = PullRequest.new(
        repository:      @source,
        base_repository: @source,
        base_user:       @admin,
        base_ref:        "master",
        head_repository: @fork,
        head_user:       @fork.owner,
        head_ref:        @head_branch,
        issue:           @issue,
        user:            @fork.owner,
      )
      issue.pull_request = @pull
      @pull.save!

      push = T.let(nil, T.untyped)
      perform_enqueued_jobs(only: [CreateCheckSuitesJob]) do
        push = push_changes(repository: @fork, branch_name: @head_branch, create_via_hydro_job: true)
      end
      check_suite = CheckSuite.where(push_id: push&.id).last
      assert check_suite, "Expected a check_suite to be created on @fork repo"

      refute_includes @pull.matching_check_suites(head_sha: @sha), check_suite
    end
  end

  context "PullRequest#action_required_check_suites" do
    test "returns an action_required check suite for the given sha" do
      check_suite = create(:check_suite_for_actions_app, :completed, repository: @pull.repository, head_sha: @pull.head_sha, conclusion: :action_required)

      assert_includes @pull.action_required_check_suites(head_sha: @pull.head_sha), check_suite
    end

    test "ignores check suites that are not action_required" do
      create(:check_suite_for_actions_app, :success, repository: @pull.repository, head_sha: @pull.head_sha)

      assert @pull.action_required_check_suites(head_sha: @pull.head_sha).empty?
    end

    test "ignores check suites that are not from the Actions app" do
      create(:check_suite, :success, repository: @pull.repository, head_sha: @pull.head_sha)

      assert @pull.action_required_check_suites(head_sha: @pull.head_sha).empty?
    end
  end

  context "#set_auto_trigger_checks" do
    test "sets a value for this repo and app's preference" do
      @source.set_auto_trigger_checks(actor: @github_app.bot, app: @github_app, value: "true")
      key = "checks.auto_trigger_checks.#{@source.id}.#{@github_app.id}"
      value = Actions::TmpKV.for_partition_key(@github_app.id).get(key).value { nil }

      assert_equal "true", value
    end

    context "instrumentation" do
      context "bot actors" do
        test "enabled action when passed value of 'true'" do
          events = subscribe("checks.auto_trigger_enabled")

          @source.set_auto_trigger_checks(actor: @github_app.bot, app: @github_app, value: "true")

          assert event = events.pop, "expected an audit log event"
          payload = event.payload

          assert_equal "checks.auto_trigger_enabled", event.name
          assert_equal @github_app.bot.display_login, event.payload[:actor]
          assert_equal @github_app.bot.id,            event.payload[:actor_id]
          assert_equal @github_app.name,              event.payload[:app]
          assert_equal @github_app.id,                event.payload[:app_id]
        end

        test "instruments the disabled action when passed value of 'false'" do
          events = subscribe("checks.auto_trigger_disabled")

          @source.set_auto_trigger_checks(actor: @github_app.bot, app: @github_app, value: "false")

          assert event = events.pop, "expected an audit log event"
          payload = event.payload

          assert_equal "checks.auto_trigger_disabled", event.name
          assert_equal @github_app.bot.display_login,  event.payload[:actor]
          assert_equal @github_app.bot.id,             event.payload[:actor_id]
          assert_equal @github_app.name,               event.payload[:app]
          assert_equal @github_app.id,                 event.payload[:app_id]
        end
      end

      context "scoped installation actors" do
        test "enabled action when passed value of 'true'" do
          events = subscribe("checks.auto_trigger_enabled")

          scoped_installation = make_scoped_integration_installation(parent: @installation, repositories: [@source])
          @source.set_auto_trigger_checks(actor: scoped_installation, app: @github_app, value: "true")

          assert event = events.pop, "expected an audit log event"
          payload = event.payload

          assert_equal "checks.auto_trigger_enabled", event.name
          assert_equal scoped_installation.name,      event.payload[:scoped_integration_installation]
          assert_equal scoped_installation.id,        event.payload[:scoped_integration_installation_id]
          assert_equal @github_app.name,              event.payload[:app]
          assert_equal @github_app.id,                event.payload[:app_id]
        end

        test "instruments the disabled action when passed value of 'false'" do
          events = subscribe("checks.auto_trigger_disabled")

          scoped_installation = make_scoped_integration_installation(parent: @installation, repositories: [@source])
          @source.set_auto_trigger_checks(actor: scoped_installation, app: @github_app, value: "false")

          assert event = events.pop, "expected an audit log event"
          payload = event.payload

          assert_equal "checks.auto_trigger_disabled", event.name
          assert_equal scoped_installation.name,       event.payload[:scoped_integration_installation]
          assert_equal scoped_installation.id,         event.payload[:scoped_integration_installation_id]
          assert_equal @github_app.name,               event.payload[:app]
          assert_equal @github_app.id,                 event.payload[:app_id]
        end
      end

      context "installation actors" do
        test "enabled action when passed value of 'true'" do
          events = subscribe("checks.auto_trigger_enabled")

          @source.set_auto_trigger_checks(actor: @installation, app: @github_app, value: "true")

          assert event = events.pop, "expected an audit log event"
          payload = event.payload

          assert_equal "checks.auto_trigger_enabled", event.name
          # TODO: fix me in https://github.com/github/ecosystem-apps/issues/469
          assert_nil payload[:actor]
          assert_nil payload[:actor_id]

          assert_equal @installation.id, event.payload[:integration_installation_id]
          assert_equal @github_app.name, event.payload[:app]
          assert_equal @github_app.id,   event.payload[:app_id]
        end

        test "instruments the disabled action when passed value of 'false'" do
          events = subscribe("checks.auto_trigger_disabled")

          @source.set_auto_trigger_checks(actor: @installation, app: @github_app, value: "false")

          assert event = events.pop, "expected an audit log event"
          payload = event.payload

          assert_equal "checks.auto_trigger_disabled", event.name
          # TODO: fix me in https://github.com/github/ecosystem-apps/issues/469
          assert_nil payload[:actor]
          assert_nil payload[:actor_id]

          assert_equal @installation.id, event.payload[:integration_installation_id]
          assert_equal @github_app.name, event.payload[:app]
          assert_equal @github_app.id,   event.payload[:app_id]
        end
      end
    end
  end

  context "#auto_trigger_checks_for?" do
    test "returns true by default" do
      assert @source.auto_trigger_checks_for?(app_id: @github_app.id)
    end

    test "returns true if the preference for the given app is true" do
      key = "checks.auto_trigger_checks.#{@source.id}.#{@github_app.id}"

      Actions::TmpKV.for_partition_key(@github_app.id).set(key, "true")

      assert @source.auto_trigger_checks_for?(app_id: @github_app.id)
    end

    test "returns false if the preference for the given app is false" do
      key = "checks.auto_trigger_checks.#{@source.id}.#{@github_app.id}"

      Actions::TmpKV.for_partition_key(@github_app.id).set(key, "false")

      refute @source.auto_trigger_checks_for?(app_id: @github_app.id)
    end
  end

  context "PullRequest#latest_check_runs_count" do
    test "returns the count of checks for the matching_check_suites" do
      assert_equal 0, @pull.latest_check_runs_count

      create :check_run, check_suite: CheckSuite.where(push_id: @push.id).last

      assert_equal 1, @pull.latest_check_runs_count
    end
  end

  test "returns a check suite created after updating the head branch from base" do
    previous_head = @pull.head_sha
    ref = @pull.repository.heads.find(@pull.base_ref)
    metadata = { message: "commit", committer: @pull.user }
    ref.append_commit(metadata, @pull.user) do |files|
      files.add("filename", "test content at #{Time.now.to_f}")
    end

    with_enqueued_pr_sync_jobs(additional_jobs: [CreateCheckSuitesJob]) do
      # Update head branch from base
      @pull.merge_base_into_head(user: @admin)
    end
    refute_equal previous_head, @pull.reload.head_sha
    push = push_accessor.latest_for_repo(repository_id: @pull.head_repository.id)
    check_suite = CheckSuite.where(push_id: push&.id).where(github_app_id: @github_app.id).last

    assert_includes @pull.matching_check_suites, check_suite
  end
end
