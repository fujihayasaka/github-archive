# typed: true
# frozen_string_literal: true

require "test_helper"

class ActionsPreviousOutcomeReuseTest < GitHub::TestCase
  fixtures do
    make_trusted_oauth_apps_owner
    @github_app = create(:launch_integration)
    GitHub.stubs(:launch_github_app).returns(@github_app)

    @user = create(:user, plan:  "pro")
    @other_user = create(:user, plan:  "pro")
    @repository = create(:repository, name: "hello-world", owner: @user, from_example: :rebase_pull_request)


    commit = @repository.heads.find("contrib").append_commit({ message: "blah", committer: @user }, @user) do |files|
      files.add("foo", "dsfdsfsdfsd")
    end
    @sha = commit.oid

    commit_metadata = { committer: @user, message: "An extra commit that will trigger a check suite clone" }
    commit = @repository.commits.create(commit_metadata) {}
    @push = create(:push, pusher: @user, after: commit.oid, repository: @repository)
    @clone_sha = commit.oid
    @check_suite = create(:check_suite_for_actions_app, repository: @repository, head_sha: @sha, event: "pull_request", head_branch: "monalisa-revert-tire-fire")
    @check_run = create(:check_run_for_actions_app, :with_steps, :success, check_suite: @check_suite)
    @check_run.workflow_job_run.update(
      parent_job_id: "build",
      job_key: "build.__default",
      summary_url: "https://github.test/summary_url"
    )
    @annotation = create(:check_annotation, check_run: @check_run, message: "hello there")

    @workflow_run = @check_suite.workflow_run
    @workflow_run.tree_id = @sha
    @execution_graph = "{\"stages\":[{\"groups\":[{\"id\":\"|\",\"type\":0,\"jobs\":[{\"id\":\"build\"}]}]}]}"
    @workflow_run.execution_graph = @execution_graph
    @workflow_run.save!
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
  end

  test "successfully create a clone of an existing actions run" do
    cloned_check_suite = Actions::PreviousOutcomeReuse.call(
      existing_check_suite_to_clone: @check_suite,
      clone_check_suite_head_sha: @clone_sha,
      clone_trigger: @push,
      clone_creator: @other_user,
      clone_event: "push",
      clone_head_branch: "main",
      tree_id: @sha,
    )

    # search for cloned check suite to make sure it exists
    assert CheckSuite.find(cloned_check_suite.id).present?

    # the check suite was successfully cloned
    assert_equal @other_user, cloned_check_suite.creator
    assert_equal @clone_sha, cloned_check_suite.head_sha

    refute_equal @check_suite.external_id, cloned_check_suite.external_id
    assert_equal @check_suite.external_id, cloned_check_suite.original_actions_external_id

    refute_equal @check_suite.event, cloned_check_suite.event
    assert_equal "push", cloned_check_suite.event

    refute_equal @check_suite.head_branch, cloned_check_suite.head_branch
    assert_equal "main", cloned_check_suite.head_branch

    # the workflow run was successfully cloned
    cloned_workflow_run = Actions::WorkflowRun.with_execution_graph.where(check_suite: cloned_check_suite, repository: @repository).first

    assert cloned_workflow_run.present?
    assert_equal @workflow_run.id, cloned_workflow_run&.cloned_workflow_run_id
    assert_equal @push, cloned_workflow_run&.trigger
    assert_equal @execution_graph, cloned_workflow_run&.execution_graph

    # check runs were successfully cloned
    cloned_check_run = cloned_check_suite.check_runs.first

    assert_equal 1, cloned_check_suite.check_runs.count
    assert_equal @check_run.name, cloned_check_run.name
    assert_equal @check_run.conclusion, cloned_check_run.conclusion
    assert_equal @check_run.external_id, cloned_check_run.external_id

    # annotations are succesfully cloned
    cloned_annotation = cloned_check_run.annotations.first

    assert_equal @check_run.annotations.count, cloned_check_run.annotations.count
    assert_equal @annotation.message, cloned_annotation.message
    assert_equal @annotation.warning_level, cloned_annotation.warning_level

    # workflow_job_run fields need certain fields to be set so that execution graph correctly gets rendered
    cloned_workflow_job_run = cloned_check_run.workflow_job_run
    assert cloned_workflow_job_run.present?
    assert_equal "build", cloned_workflow_job_run.parent_job_id
    assert_equal "build.__default", cloned_workflow_job_run.job_key
    assert_equal "https://github.test/summary_url", cloned_workflow_job_run.summary_url
  end

  test "skips cloning steps" do
    cloned_check_suite = Actions::PreviousOutcomeReuse.call(
      existing_check_suite_to_clone: @check_suite,
      clone_check_suite_head_sha: @clone_sha,
      clone_trigger: @push,
      clone_creator: @other_user,
      clone_event: "push",
      clone_head_branch: "main",
      tree_id: @sha,
    )

    # search for cloned check suite to make sure it exists
    assert CheckSuite.find(cloned_check_suite.id).present?
    cloned_check_run = cloned_check_suite.check_runs.first

    # check steps from each check run were not cloned
    refute_empty @check_run.steps.to_a
    assert_empty cloned_check_run.steps.to_a
  end

  test "merge queue gets a notification if the check suite is related to it" do
    # Create the MergeQueue and create a fake Entry that has the same SHA as the setup block.
    merge_queue = create(:merge_queue, repository: @repository, branch: @repository.default_branch, merge_method: "merge")
    merge_queue_entry = create(:merge_queue_entry, queue: merge_queue, head_sha: @clone_sha)

    assert_enqueued_with(job: MergeQueueShaUpdateJob) do
      Actions::PreviousOutcomeReuse.call(
        existing_check_suite_to_clone: @check_suite,
        clone_check_suite_head_sha: @clone_sha,
        clone_trigger: @push,
        clone_creator: @other_user,
        clone_event: "merge_group",
        clone_head_branch: "main",
        tree_id: @sha,
      )
    end
  end
end
