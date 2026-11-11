# typed: true
# frozen_string_literal: true

class Actions::PreviousOutcomeReuse

  attr_reader :existing_check_suite_to_clone

  def self.call(existing_check_suite_to_clone:, clone_check_suite_head_sha:, clone_trigger:, clone_creator:, clone_event:, clone_head_branch:, tree_id:)
    new(
      existing_check_suite_to_clone: existing_check_suite_to_clone,
      clone_check_suite_head_sha: clone_check_suite_head_sha,
      clone_trigger: clone_trigger,
      clone_creator: clone_creator,
      clone_event: clone_event,
      clone_head_branch: clone_head_branch,
      tree_id: tree_id,
    ).call
  end

  def initialize(existing_check_suite_to_clone:, clone_check_suite_head_sha:, clone_trigger:, clone_creator:, clone_event:, clone_head_branch:, tree_id:)
    @existing_check_suite_to_clone = existing_check_suite_to_clone
    @clone_check_suite_head_sha = clone_check_suite_head_sha
    @clone_trigger = clone_trigger
    @clone_creator = clone_creator
    @clone_event = clone_event
    @clone_head_branch = clone_head_branch
    @tree_id = tree_id
  end

  def call
    # reuse only available for actions runs
    return unless existing_check_suite_to_clone.actions_app?

    existing_workflow_run = Actions::WorkflowRun.with_execution_graph.where(check_suite: existing_check_suite_to_clone, repository_id: existing_check_suite_to_clone.repository_id).first
    return unless existing_workflow_run.present?
    return unless existing_check_suite_to_clone.completed? && existing_check_suite_to_clone.conclusion == "success"

    # the provided tree_id must match the existing workflow run's tree_id
    return unless existing_workflow_run.tree_id == @tree_id

    # clone the existing check_suite
    check_suite_clone = existing_check_suite_to_clone.dup
    check_suite_clone.external_id = existing_check_suite_to_clone.new_unique_external_id_for_clone
    check_suite_clone.rerequestable = false

    # the check suite duration gets calculated using started_at and completed_at so this ensures it shows up as 0
    check_suite_clone.started_at = Time.now
    check_suite_clone.completed_at = Time.now

    # the new check suite should target a different head_sha/commit and the creator of the check_suite can be different
    check_suite_clone.head_sha = @clone_check_suite_head_sha
    check_suite_clone.creator = @clone_creator

    # reused check suites can originate from different events that have different branches, a PR event for example may reuse a push event that has the same tree_id
    check_suite_clone.event = @clone_event
    if @clone_head_branch.present?
      check_suite_clone.head_branch = @clone_head_branch
    end

    check_suite_clone.workflow_run_data = Actions::WorkflowRunData.new(
      tree_id: existing_workflow_run.tree_id,
      workflow_execution_graph: existing_workflow_run.execution_graph,
      cloned_workflow_run_id: existing_workflow_run.id,
      trigger: @clone_trigger
    )
    check_suite_clone.save!

    # clone all check runs (actions jobs), their steps, and annotations
    existing_check_suite_to_clone.check_runs.each do |existing_check_run|
      check_run_clone = existing_check_run.dup
      check_run_clone.check_suite = check_suite_clone

      # Transient fields that will be assigned to the workflow job after the check run is created
      existing_workflow_job_run = existing_check_run.workflow_job_run
      if existing_workflow_job_run.present?
        check_run_clone.parent_job_id = existing_workflow_job_run.parent_job_id
        check_run_clone.job_key = existing_workflow_job_run.job_key
        check_run_clone.summary_url = existing_workflow_job_run.summary_url
      end

      check_run_clone.save!

      # Steps are intentionally not cloned to avoid creating
      # more steps in the database for old runs
      # See https://github.com/github/actions-relaunch/issues/819.

      existing_check_run.annotations.each do |exisiting_annotation|
        annotation_clone = exisiting_annotation.dup
        annotation_clone.check_run = check_run_clone
        annotation_clone.save!
      end
    end

    if @clone_event == "merge_group"
      MergeQueues.execute_from_sha!(check_suite_clone.repository, @clone_check_suite_head_sha)
    end

    # update the original workflow run with an id of itself so it knows that it was cloned
    # an empty cloned_workflow_run_id means that the workflow run was not cloned while an id that matches itself represents a reused workflow run that was cloned
    existing_workflow_run.update(cloned_workflow_run_id: existing_workflow_run.id)

    check_suite_clone
  end
end
