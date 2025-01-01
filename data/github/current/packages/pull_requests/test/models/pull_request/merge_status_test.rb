# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestMergeStatusTest < GitHub::TestCase

  def make_status(pull, state, context = "default")
    create(:status, repository: pull.repository,
                creator: pull.repository.owner,
                state: state,
                sha: pull.head_sha,
                context: context)
  end

  fixtures do
    @repo = create(:repository, from_example: :pull_request_source)
  end

  setup do
    @owner = @repo.owner
    @pull = PullRequest.create_for!(
      @repo,
      title: "blah",
      body: "blah",
      user: @owner,
      base: "master",
      head: "master-forward-2",
    )
  end

  def create_pr(user, repo, headref)
    create(:pull_request,
      repository: repo,
      base_repository: repo,
      base_user: repo.owner,
      base_ref: "master",
      head_repository: repo,
      head_user: repo.owner,
      head_ref: headref,
      user: user,
      )
  end

  context "with expected statuses" do
    test "works when travis-ci is expected" do
      protected_branch = create(:protected_branch, repository: @repo, creator: @owner, required_status_checks_enforcement_level: :non_admins)
      protected_branch.replace_status_contexts(%w[continuous-integration/travis-ci])

      merge_status = PullRequest::MergeStatus.new(@repo, @pull.head_sha, target_branch: "master", check_runs: [])
      assert_equal 1, merge_status.status_checks.length
      assert_equal "continuous-integration/travis-ci", merge_status.status_checks.first.context
    end

    test "does not include expected statuses when required status checks are disabled" do
      protected_branch = @repo.protect_branch("master", creator: @owner, required_status_checks: { contexts: %w[ci/janky], include_admins: true }, entry_point: :test_case)
      # Now disable required status checks
      protected_branch.required_status_checks_enforcement_level = :off
      protected_branch.save!

      make_status @pull, "success", "circle-ci"

      merge_status = PullRequest::MergeStatus.new(@repo, @pull.head_sha, target_branch: "master", check_runs: [])
      assert_equal %w[circle-ci], merge_status.status_checks.map(&:context)
    end

    test "works with a check run in a check suite with a name and/or event" do
      protected_branch = @repo.protect_branch("master", creator: @owner, required_status_checks: { contexts: %w[ci/janky], include_admins: true }, entry_point: :test_case)
      protected_branch.replace_status_contexts(%w[github])

      check_suite  = create(:check_suite, repository: @repo, head_sha: @pull.head_sha, name: "CI build", event: "push")
      check_run    = create(:check_run, name: "github", check_suite: check_suite, status: :completed, completed_at: 1.day.ago, conclusion: :success)

      merge_status = PullRequest::MergeStatus.new(@repo, @pull.head_sha, target_branch: "master", check_runs: [check_run])

      assert_equal %w[github], merge_status.status_checks.map(&:context)
      refute merge_status.incomplete?
    end
  end

  context "merge statuses for pulls" do
    test "fills statuses and check runs for pulls" do
      user = @owner
      repo = create :repository, owner: user, name: "hello-world", from_example: :rebase_pull_request

      protected_branch = create(:protected_branch, repository: repo, creator: user, required_status_checks_enforcement_level: :non_admins)
      protected_branch.replace_status_contexts(%w[continuous-integration/travis-ci])

      pull_1 = create_pr(user, repo, "contrib")
      pull_2 = create_pr(user, repo, "readme-title")

      check_suite = create(:check_suite, repository: repo, head_sha: pull_1.head_sha, name: "CI build", event: "push")
      coverage_check_run = create(:check_run, name: "coverage", check_suite: check_suite, status: :completed, completed_at: 1.day.ago, conclusion: :success)
      report_check_run    = create(:check_run, name: "report", check_suite: check_suite, status: :completed, completed_at: 1.day.ago, conclusion: :success)

      sha2_check_suite = create(:check_suite, repository: repo, head_sha: pull_2.head_sha, name: "CI build", event: "push")
      linter_check_run    = create(:check_run, name: "linter", check_suite: sha2_check_suite, status: :completed, completed_at: 1.day.ago, conclusion: :success)

      PullRequest.attach_statuses(repo, [pull_1, pull_2], with_check_runs: true, current_user: user)

      assert_same_elements pull_1.combined_status.latest_check_runs_by_name.map(&:id), [coverage_check_run.id, report_check_run.id]
      assert_equal "continuous-integration/travis-ci", pull_1.combined_status.status_checks[0].context

      assert_same_elements pull_2.combined_status.latest_check_runs_by_name.map(&:id), [linter_check_run.id]
      assert_equal "continuous-integration/travis-ci", pull_2.combined_status.status_checks[0].context
    end

    test "fills statuses and check runs for pulls with failing status" do
      user = @owner
      repo = create :repository, owner: user, name: "hello-world", from_example: :rebase_pull_request

      protected_branch = create(:protected_branch, repository: repo, creator: user, required_status_checks_enforcement_level: :non_admins)
      protected_branch.replace_status_contexts(%w[continuous-integration/travis-ci])

      pull_1 = create_pr(user, repo, "contrib")
      pull_2 = create_pr(user, repo, "readme-title")

      check_suite = create(:check_suite, repository: repo, head_sha: pull_1.head_sha, name: "CI build", event: "push")
      coverage_check_run = create(:check_run, name: "coverage", check_suite: check_suite, status: :completed, completed_at: 1.day.ago, conclusion: :failure)
      report_check_run    = create(:check_run, name: "report", check_suite: check_suite, status: :completed, completed_at: 1.day.ago, conclusion: :failure)

      sha2_check_suite = create(:check_suite, repository: repo, head_sha: pull_2.head_sha, name: "CI build", event: "push")
      linter_check_run    = create(:check_run, name: "linter", check_suite: sha2_check_suite, status: :completed, completed_at: 1.day.ago, conclusion: :failure)

      PullRequest.attach_statuses(repo, [pull_1, pull_2], with_check_runs: true, current_user: user)
      assert_same_elements pull_1.combined_status.latest_check_runs_by_name.map(&:id), [coverage_check_run.id, report_check_run.id]
      assert_equal "continuous-integration/travis-ci", pull_1.combined_status.status_checks[0].context

      assert_same_elements pull_2.combined_status.latest_check_runs_by_name.map(&:id), [linter_check_run.id]
      assert_equal "continuous-integration/travis-ci", pull_2.combined_status.status_checks[0].context
    end
  end

  if !GitHub.enterprise?
    test "de-duplicate job statuses from required ruleset workflows" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      org = create(:organization, plan: "business_plus")
      source_repo = create(:repository, owner: org)
      target_repo = create(:repository, owner: org, from_example: :pull_request_source)

      ruleset_workflow_path = ".github/workflows/test.yml"
      ruleset_workflow_ref = source_repo.heads.read(source_repo.default_branch)

      ruleset_workflow_ref.append_commit({ message: "add workflow", committer: source_repo.owner.admin }, source_repo.owner) do |files|
        files.add(ruleset_workflow_path, "some content")
      end

      ruleset = create :repository_ruleset, :targets_default_branch, :targets_all_repos, source: org
      configuration = create(:repository_rule_configuration, rule_type: "workflows", repository_ruleset: ruleset, parameters: {
        workflows: [{
          repository_id: source_repo.id,
          path: ruleset_workflow_path,
          ref: "refs/heads/#{source_repo.default_branch}"
        }]
      })

      before = target_repo.heads[target_repo.default_branch].target_oid
      after = target_repo.commits.create({ message: "New commit", committer: target_repo.owner }, before) do |files|
        files.add "New file", "New file"
      end.oid

      pull = create :pull_request, :with_mergeable_head, repository: target_repo
      check_suite = create(:check_suite_for_actions_app, repository: target_repo, head_sha: pull.head_sha, name: "CI", event: "pull_request", workflow_file_path: "required/#{source_repo.id}/#{ruleset_workflow_path}")
      check_run = create :check_run_for_actions_app, check_suite: check_suite, name: "req-workflow-context1", status: "pending", conclusion: nil

      CheckSuite.any_instance.stubs(:imposer_repo_id).returns(source_repo.id)
      Actions::WorkflowRun.any_instance.stubs(:workflow_file_ref).returns("refs/heads/#{source_repo.default_branch}")

      merge_status = PullRequest::MergeStatus.new(target_repo, pull.head_sha, target_branch: target_repo.default_branch)

      assert_equal 1, merge_status.status_checks.length
      assert merge_status.status_checks.first.is_a?(RuleEngine::Rules::WorkflowRule::RequiredWorkflowStatusCheckDuckType)
      assert_equal check_suite, merge_status.status_checks.first.check_suite
    end
  end

  if !GitHub.enterprise?
    test "shows only latest check suite on re-open for required workflows" do
      Spokesd.enable_spokesd

      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      org = create(:organization, plan: "business_plus")
      source_repo = create(:repository, owner: org)
      target_repo = create(:repository, owner: org, from_example: :pull_request_source)

      ruleset_workflow_path = ".github/workflows/test.yml"
      ruleset_workflow_ref = source_repo.heads.read(source_repo.default_branch)

      ruleset_workflow_ref.append_commit({ message: "add workflow", committer: source_repo.owner.admin }, source_repo.owner) do |files|
        files.add(ruleset_workflow_path, "some content")
      end

      ruleset = create :repository_ruleset, :targets_default_branch, :targets_all_repos, source: org
      configuration = create(:repository_rule_configuration, rule_type: "workflows", repository_ruleset: ruleset, parameters: {
        workflows: [{
          repository_id: source_repo.id,
          path: ruleset_workflow_path,
          ref: "refs/heads/#{source_repo.default_branch}"
        }]
      })

      before = target_repo.heads[target_repo.default_branch].target_oid
      after = target_repo.commits.create({ message: "New commit", committer: target_repo.owner }, before) do |files|
        files.add "New file", "New file"
      end.oid

      pull = create :pull_request, :with_mergeable_head, repository: target_repo
      check_suite = create(:check_suite_for_actions_app, repository: target_repo, head_sha: pull.head_sha, name: "CI", event: "pull_request", workflow_file_path: "required/#{source_repo.id}/#{ruleset_workflow_path}")
      check_run = create :check_run_for_actions_app, check_suite: check_suite, name: "req-workflow-context1", status: "pending", conclusion: nil

      Timecop.travel(10.minutes) do
        check_suite_2 = create(:check_suite_for_actions_app, repository: target_repo, head_sha: pull.head_sha, name: "CI", event: "pull_request", workflow_file_path: "required/#{source_repo.id}/#{ruleset_workflow_path}")
        check_run_2 = create :check_run_for_actions_app, check_suite: check_suite, name: "req-workflow-context1", status: "pending", conclusion: nil

        CheckSuite.any_instance.stubs(:imposer_repo_id).returns(source_repo.id)
        Actions::WorkflowRun.any_instance.stubs(:workflow_file_ref).returns("refs/heads/#{source_repo.default_branch}")

        pull.close(pull.user)
        pull.reopened(pull.user)

        merge_status = PullRequest::MergeStatus.new(target_repo, pull.head_sha, target_branch: target_repo.default_branch)

        assert_equal 1, merge_status.status_checks.length
        assert merge_status.status_checks.first.is_a?(RuleEngine::Rules::WorkflowRule::RequiredWorkflowStatusCheckDuckType)
        assert_equal check_suite_2, merge_status.status_checks.first.check_suite
      end
    end
  end
end
