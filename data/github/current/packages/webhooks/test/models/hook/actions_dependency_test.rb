# typed: true
# frozen_string_literal: true

require "test_helper"

class HookActionsDependencyTest < GitHub::TestCase

  fixtures do
    make_trusted_oauth_apps_owner
    @actions_app = create(:launch_integration, :with_active_hook, default_permissions: Apps::Privileged::Actions::PERMISSIONS, default_events: %w(status workflow_run push issues))
    GitHub.stubs(:launch_github_app).returns(@actions_app)

    @org = create(:organization)
    @actions_repo = create :repository, owner: @org, from_example: :post_receive_job_test
    example_repo_snapshot

    @user = create(:user)

    GitHub.stubs(:actions_enabled?).returns(true)

    @actions_check_suite = create(:check_suite_for_actions_app,
      creator: GitHub.launch_github_app.bot,
      repository: @actions_repo)
    @actions_created_workflow_run = @actions_check_suite.workflow_run
  end

  setup do
    example_repo_restore
    GitHub.stubs(:actions_enabled?).returns(true)
    GitHub.stubs(:launch_github_app).returns(@actions_app)
  end

  test "true for workflow run triggered by the Actions bot user when flag is disabled" do
    GitHub.flipper[:workflow_run_is_not_filtered].disable
    event = Hook::Event::WorkflowRunEvent.new(run_id: @actions_created_workflow_run.id, action: "completed")

    delivery_system = Hook::DeliverySystem.new event

    assert_equal GitHub.launch_github_app.bot, event.actor
    assert delivery_system.is_filterable_actions_triggered_event?
  end

  test "false for workflow run triggered by the Actions bot user when the flag is enabled" do
    GitHub.flipper[:workflow_run_is_not_filtered].enable
    event = Hook::Event::WorkflowRunEvent.new(run_id: @actions_created_workflow_run.id, action: "completed")

    delivery_system = Hook::DeliverySystem.new event

    assert_equal GitHub.launch_github_app.bot, event.actor
    refute delivery_system.is_filterable_actions_triggered_event?
  end

  test "false for events triggered by another user" do
    event = Hook::Event::StatusEvent.new status: create(:status, repository: @actions_repo)

    delivery_system = Hook::DeliverySystem.new event

    refute_equal GitHub.launch_github_app.bot, event.actor
    refute delivery_system.is_filterable_actions_triggered_event?
  end

  test "true for Actions check suite" do
    check_suite = create(:check_suite_for_actions_app, repository: @actions_repo)
    event = Hook::Event::CheckSuiteEvent.new(check_suite_id: check_suite.id, action: "created")

    delivery_system = Hook::DeliverySystem.new event

    refute_equal GitHub.launch_github_app.bot, event.actor
    assert_equal GitHub.launch_github_app, event.app
    assert delivery_system.is_filterable_actions_triggered_event?
  end

  test "false for Actions check suite rerequested events" do
    check_suite = create(:check_suite_for_actions_app, repository: @actions_repo)
    event = Hook::Event::CheckSuiteEvent.new(check_suite_id: check_suite.id, action: "rerequested")

    delivery_system = Hook::DeliverySystem.new event

    refute_equal GitHub.launch_github_app.bot, event.actor
    assert_equal GitHub.launch_github_app, event.app
    refute delivery_system.is_filterable_actions_triggered_event?
  end

  test "false for other GitHub App check suites" do
    check_suite = create(:check_suite, repository: @actions_repo)
    event = Hook::Event::CheckSuiteEvent.new(check_suite_id: check_suite.id, action: "created")

    delivery_system = Hook::DeliverySystem.new event

    refute_equal GitHub.launch_github_app.bot, event.actor
    refute_equal GitHub.launch_github_app, event.app
    refute delivery_system.is_filterable_actions_triggered_event?
  end

  test "true for Actions check run" do
    check_suite = create(:check_suite_for_actions_app, repository: @actions_repo)
    check_run = create(:check_run, check_suite: check_suite)
    event = Hook::Event::CheckRunEvent.new(check_run_id: check_run.id, action: "created")

    delivery_system = Hook::DeliverySystem.new event

    refute_equal GitHub.launch_github_app.bot, event.actor
    assert_equal GitHub.launch_github_app, event.app
    assert delivery_system.is_filterable_actions_triggered_event?
  end

  test "false for other GitHub App check runs" do
    check_suite = create(:check_suite, repository: @actions_repo)
    check_run = create(:check_run, check_suite: check_suite)
    event = Hook::Event::CheckRunEvent.new(check_run_id: check_run.id, action: "created")

    delivery_system = Hook::DeliverySystem.new event

    refute_equal GitHub.launch_github_app.bot, event.actor
    refute_equal GitHub.launch_github_app, event.app
    refute delivery_system.is_filterable_actions_triggered_event?
  end

  test "false for push events" do
    event = Hook::Event::PushEvent.new({
      repo: @actions_repo,
      before: "c1800491d95c42b4e96fb83f31fe8d9230c62907",
      after: "63611721afd41f58f801d66e543d8288b4c5eb44",
      ref: "refs/heads/master",
      pusher: create(:user),
    })

    delivery_system = Hook::DeliverySystem.new event

    refute_equal GitHub.launch_github_app.bot, event.actor
    refute delivery_system.is_filterable_actions_triggered_event?
  end

  test "false for push events from the Actions bot user" do
    event = Hook::Event::PushEvent.new({
      repo: @actions_repo,
      before: "c1800491d95c42b4e96fb83f31fe8d9230c62907",
      after: "63611721afd41f58f801d66e543d8288b4c5eb44",
      ref: "refs/heads/master",
      pusher: GitHub.launch_github_app.bot,
    })

    delivery_system = Hook::DeliverySystem.new event

    assert_equal GitHub.launch_github_app.bot, event.actor
    refute delivery_system.is_filterable_actions_triggered_event?
  end

  test "false for workflow dispatch from the actions bot" do
    event = Hook::Event::WorkflowDispatchEvent.new({
      repository_id: @actions_repo.id,
      ref: "refs/heads/master",
      workflow: ".github/workflows/workflow.yml",
      actor_id:  GitHub.launch_github_app.bot.id
    })

    delivery_system = Hook::DeliverySystem.new event
    assert_equal GitHub.launch_github_app.bot, event.actor
    refute delivery_system.is_filterable_actions_triggered_event?
  end

  test "false for repository dispatch from the actions bot" do
    event = Hook::Event::RepositoryDispatchEvent.new({
      repository_id: @actions_repo.id,
      actor_id:  GitHub.launch_github_app.bot.id,
      action: "created",
      branch: @actions_repo.default_branch,
    })

    delivery_system = Hook::DeliverySystem.new event
    assert_equal GitHub.launch_github_app.bot, event.actor
    refute delivery_system.is_filterable_actions_triggered_event?
  end

  context "#require_on_demand_actions_app_installation?" do
    test "return false for events other than pull_request" do
      test_repo = create(:repository, owner: @org)
      event = Hook::Event::RepositoryDispatchEvent.new({
        repository_id: test_repo.id,
        actor_id:  GitHub.launch_github_app.bot.id,
        action: "created",
        branch: test_repo.default_branch,
      })

      delivery_system = Hook::DeliverySystem.new event

      refute delivery_system.require_on_demand_actions_app_installation?
    end

    test "return false when the required workflows on demand app installation feature flag is disabled" do
      GitHub.flipper[:actions_required_workflows_on_demand_app_installation].disable

      test_repo = create(:repository, owner: @org, from_example: :rebase_pull_request)
      issue = create(:issue, user: @user, repository: test_repo)
      pull = create(:pull_request,
        repository: test_repo,
        base_repository: test_repo,
        base_user: test_repo.owner,
        base_ref: "master",
        head_repository: test_repo,
        head_user: test_repo.owner,
        head_ref: "contrib",
        issue: issue,
      )
      event = Hook::Event::PullRequestEvent.new action: :created, pull_request_id: pull.id

      delivery_system = Hook::DeliverySystem.new event
      refute delivery_system.require_on_demand_actions_app_installation?
    end

    test "return false when the actions_required_workflows_on_demand_app_installation feature flag is disabled" do
      GitHub.flipper[:actions_required_workflows_on_demand_app_installation].disable

      test_repo = create(:repository, owner: @org, from_example: :rebase_pull_request)
      issue = create(:issue, user: @user, repository: test_repo)
      pull = create(:pull_request,
        repository: test_repo,
        base_repository: test_repo,
        base_user: test_repo.owner,
        base_ref: "master",
        head_repository: test_repo,
        head_user: test_repo.owner,
        head_ref: "contrib",
        issue: issue,
      )
      event = Hook::Event::PullRequestEvent.new action: :created, pull_request_id: pull.id

      delivery_system = Hook::DeliverySystem.new event
      refute delivery_system.require_on_demand_actions_app_installation?
    end

    test "return false when the actions app is already installed on the repo" do
      GitHub.flipper[:actions_required_workflows_on_demand_app_installation].enable

      test_repo = create(:repository, owner: @org, from_example: :rebase_pull_request)
      issue = create(:issue, user: @user, repository: test_repo)
      pull = create(:pull_request,
        repository: test_repo,
        base_repository: test_repo,
        base_user: test_repo.owner,
        base_ref: "master",
        head_repository: test_repo,
        head_user: test_repo.owner,
        head_ref: "contrib",
        issue: issue,
      )
      event = Hook::Event::PullRequestEvent.new action: :created, pull_request_id: pull.id

      test_repo.enable_actions_app(entry_point: :test_case)
      delivery_system = Hook::DeliverySystem.new event
      refute delivery_system.require_on_demand_actions_app_installation?
    end

    test "return false when there are no required workflows configured" do
      GitHub.flipper[:actions_required_workflows_on_demand_app_installation].enable

      test_repo = create(:repository, owner: @org, from_example: :rebase_pull_request)
      issue = create(:issue, user: @user, repository: test_repo)
      pull = create(:pull_request,
        repository: test_repo,
        base_repository: test_repo,
        base_user: test_repo.owner,
        base_ref: "master",
        head_repository: test_repo,
        head_user: test_repo.owner,
        head_ref: "contrib",
        issue: issue,
      )
      event = Hook::Event::PullRequestEvent.new action: :created, pull_request_id: pull.id

      delivery_system = Hook::DeliverySystem.new event
      refute delivery_system.require_on_demand_actions_app_installation?
    end

    test "return true when there is at least one enabled ruleset workflow configured and imposed on the repo" do
      GitHub.flipper[:actions_required_workflows_on_demand_app_installation].enable

      org = create(:organization, admin: @user, plan: "business_plus")
      workflow_repo = create(:repository, owner: org, admin: @user, from_example: :rebase_pull_request)

      ruleset_workflow_path = ".github/workflows/workflow.yml"
      ruleset_workflow_ref = "refs/heads/master"

      workflow_repo.heads[ruleset_workflow_ref].append_commit({ message: "add workflow", committer: @user }, workflow_repo.owner) do |files|
        files.add(ruleset_workflow_path, "some content")
      end

      ruleset = create :repository_ruleset, :targets_default_branch, :targets_all_repos, source: org, enforcement: :enabled
      create(:repository_rule_configuration, rule_type: "workflows", repository_ruleset: ruleset, parameters: {
        workflows: [{
          repository_id: workflow_repo.id,
          path: ruleset_workflow_path,
          ref: "refs/heads/master"
        }]
      })

      before = workflow_repo.heads["refs/heads/master"].target_oid
      after = workflow_repo.commits.create({ message: "New commit", committer: @user }, before) do |files|
        files.add "New file", "New file"
      end.oid

      issue = create(:issue, user: @user, repository: workflow_repo)
      pull = create(:pull_request,
        repository: workflow_repo,
        base_repository: workflow_repo,
        base_user: @user,
        base_ref: "refs/heads/master",
        head_repository: workflow_repo,
        head_user: @user,
        head_ref: "contrib",
        issue: issue,
      )

      event = Hook::Event::PullRequestEvent.new action: :created, pull_request_id: pull.id

      delivery_system = Hook::DeliverySystem.new event
      assert delivery_system.require_on_demand_actions_app_installation?
    end

    test "return true when there is at least one evaluate ruleset workflow configured and imposed on the repo" do
      GitHub.flipper[:actions_required_workflows_on_demand_app_installation].enable

      org = create(:organization, admin: @user, plan: "business_plus")
      workflow_repo = create(:repository, owner: org, admin: @user, from_example: :rebase_pull_request)

      ruleset_workflow_path = ".github/workflows/workflow.yml"
      ruleset_workflow_ref = "refs/heads/master"

      workflow_repo.heads[ruleset_workflow_ref].append_commit({ message: "add workflow", committer: @user }, workflow_repo.owner) do |files|
        files.add(ruleset_workflow_path, "some content")
      end

      ruleset = create :repository_ruleset, :targets_default_branch, :targets_all_repos, source: org, enforcement: :evaluate
      create(:repository_rule_configuration, rule_type: "workflows", repository_ruleset: ruleset, parameters: {
        workflows: [{
          repository_id: workflow_repo.id,
          path: ruleset_workflow_path,
          ref: "refs/heads/master"
        }]
      })

      before = workflow_repo.heads["refs/heads/master"].target_oid
      after = workflow_repo.commits.create({ message: "New commit", committer: @user }, before) do |files|
        files.add "New file", "New file"
      end.oid

      issue = create(:issue, user: @user, repository: workflow_repo)
      pull = create(:pull_request,
        repository: workflow_repo,
        base_repository: workflow_repo,
        base_user: @user,
        base_ref: "refs/heads/master",
        head_repository: workflow_repo,
        head_user: @user,
        head_ref: "contrib",
        issue: issue,
      )

      event = Hook::Event::PullRequestEvent.new action: :created, pull_request_id: pull.id

      delivery_system = Hook::DeliverySystem.new event
      assert delivery_system.require_on_demand_actions_app_installation?
    end
  end
end
