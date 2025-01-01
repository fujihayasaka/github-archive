# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "integration_test_case"

module MergeQueues
  class RulesetWorkflowTest < IntegrationTestCase
    fixtures do
      make_trusted_oauth_apps_owner
      create(:merge_queue_integration)

      @org = create(:organization, plan: "business_plus")
      @repo = create(:public_repository, :has_merge_queue, owner: @org)
      @user = create(:user)
      @repo.add_member @user, action: :write
      @org.add_member @user, action: :write

      @queue = @repo.default_merge_queue

      disable_feature_flag(:merge_queue_uses_queue_refs, @repo)

      create :hook, :web, installation_target: @repo, events: %w(merge_group pull_request)

      example_repo_snapshot
    end

    test "a PR is enqueued, and only has ruleset workflows" do
      @queue.protected_branch.required_status_checks.destroy_all
      @queue.protected_branch.required_status_checks_enforcement_level = "off"

      # lets set up some workflows
      @workflow_repo = create :repository, owner: @org, name: "imposer"

      @ruleset_workflow_path = ".github/workflows/required.yml"
      @ruleset_workflow_ref = "refs/heads/master"
      @required_path_for_suite = "required/#{@workflow_repo.id}/#{@ruleset_workflow_path}"

      @workflow_repo.heads.find_or_build(@queue.branch).append_commit({ message: "add workflow", committer: @user }, @user) do |files|
        files.add(@ruleset_workflow_path, "some content")
      end
      @queue_branch = @repo.heads.find(@queue.branch)


      @imposed_workflow = Actions::Workflow.new(name: "rules-only", path: @ruleset_workflow_path, imposer_repository_id: @workflow_repo.id, repository_id: @repo.id)
      @imposed_workflow.enable(@repo)
      @imposed_workflow.present_in_default_branch = true
      @imposed_workflow.save

      @required_workflow = Actions::Workflow.new(name: "rules-only", path: @ruleset_workflow_path, repository_id: @workflow_repo.id)
      @required_workflow.enable(@workflow_repo)
      @required_workflow.present_in_default_branch = true
      @required_workflow.save

      github_app  = create :integration, default_permissions: { "checks" => :write }, owner: @org, url: "http://super-duper.com"
      make_integration_installation integration: github_app, repository: @repo


      ruleset = create :repository_ruleset, :targets_all_repos, source: @org
      create(:repository_rule_condition, :targets_branch, branch_name: "refs/heads/#{@queue.branch}", repository_ruleset: ruleset)

      create(:repository_rule_configuration, rule_type: "workflows", repository_ruleset: ruleset, parameters: {
        workflows: [{
          repository_id:  @workflow_repo.id,
          path: @ruleset_workflow_path,
          ref: @ruleset_workflow_ref
        }]
      })

      pull = PullRequest.create_for!(@repo,
        base: @queue.branch,
        head: "cr-line-endings",
        user: @user,
        title: "title",
        body: "body",
      )

      pull.create_merge_commit

      suite = CheckSuite.create!({
        github_app_id: github_app.id,
        head_sha: pull.head_sha,
        repository_id: @repo.id,
        workflow_file_path: @required_path_for_suite,
        event: "pull_request",
      })
      suite.conclusion = "success"
      suite.status = "completed"
      suite.save

      @run = Actions::WorkflowRun.new(workflow: @imposed_workflow, actor: @org, repository: @repo, check_suite: suite, name: @imposed_workflow.name, workflow_file_checkout_sha: @workflow_repo.heads[@ruleset_workflow_ref].sha,
        head_branch: pull.head_ref, head_sha: pull.head_sha, workflow_file_path: @ruleset_workflow_path, imposer_repository_id: @workflow_repo.id, workflow_file_ref: @ruleset_workflow_ref)
      @run.save


      entry = @queue.enqueue!(pull_request: pull, enqueuer: @user, jump_queue: false)

      @model_cache << pull
      @model_cache << entry

      invoke_merge_queue_job!

      assert_entry_hook_delivered(entry, "checks_requested")

      suite = CheckSuite.create!({
        github_app_id: github_app.id,
        head_sha: entry.head_sha,
        repository_id: @repo.id,
        workflow_file_path: @required_path_for_suite,
        event: "merge_queue"
      })
      suite.conclusion = "success"
      suite.status = "completed"
      suite.save

      @run = Actions::WorkflowRun.new(workflow: @imposed_workflow, actor: @org, repository: @repo, check_suite: suite, name: @imposed_workflow.name, workflow_file_checkout_sha: @workflow_repo.heads[@ruleset_workflow_ref].sha,
                                      head_branch: entry.head_ref, head_sha: entry.head_sha, workflow_file_path: @ruleset_workflow_path, imposer_repository_id: @workflow_repo.id, workflow_file_ref: @ruleset_workflow_ref)
      @run.save

      # It should not queue a job in the future because everything settled.
      MergeQueues.expects(:delayed_execute!).never

      invoke_merge_queue_job!

      assert_queue_size 0

      assert pull.merged?
      assert_pull_request_hook_delivered(pull, "dequeued")

      assert entry.destroyed?
      assert_entry_hook_delivered(entry, "destroyed")
      assert_prep_branch_merged_for(pull)
      assert_prep_branch_created_for(pull)
      assert_prep_branch_deleted_for(pull)
    end
  end
end
