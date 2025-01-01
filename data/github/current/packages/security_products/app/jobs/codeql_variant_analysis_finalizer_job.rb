# typed: true
# frozen_string_literal: true

# Runs on a schedule and cleans up CodeqlVariantAnalysisRepoTask records
# that have been left in a non-final state after their workflow run has
# completed.
class CodeqlVariantAnalysisFinalizerJob < ApplicationJob
  queue_as :code_scanning_multi_repository_variant_analysis

  # this is a cross tenant background cleanup job
  exempt_from_tenant_context_requirement

  retry_on_dirty_exit

  schedule interval: 1.hour, condition: -> { !GitHub.enterprise? }

  def perform

    non_final_repo_tasks = get_non_final_repo_tasks

    variant_analyses = CodeqlVariantAnalysis
      .where(id: non_final_repo_tasks.map(&:codeql_variant_analysis_id).uniq)
      .select(:id, :actions_workflow_run_id)

    completed_workflow_run_ids = Actions::WorkflowRun
      .includes(:check_suite)
      .where(id: variant_analyses.map(&:actions_workflow_run_id))
      .filter_map { |w| w.id if w.completed? }
      .to_set

    complete_variant_analysis_ids = variant_analyses.filter_map do |v|
      v.id if completed_workflow_run_ids.include?(T.must(v.actions_workflow_run_id))
    end.to_set

    hanging_repo_tasks = non_final_repo_tasks.filter do |t|
      complete_variant_analysis_ids.include?(t.codeql_variant_analysis_id)
    end

    GitHub.dogstats.count("codeql_variant_analysis_finalizer_job.hanging_repo_tasks.count", hanging_repo_tasks.length)

    ActiveRecord::Base.connected_to(role: :writing) do
      hanging_repo_tasks.each_slice(100) do |repo_tasks_slice|
        CodeqlVariantAnalysisRepoTask.transaction do
          reloaded_repo_tasks = CodeqlVariantAnalysisRepoTask.where(id: repo_tasks_slice.map(&:id))
          reloaded_repo_tasks.each do |repo_task|
            # Make sure the repo task status hasn't been updated since we started
            if CodeqlVariantAnalysisRepoTask::NON_FINAL_STATUSES.include?(repo_task.status)
              repo_task.update(
                status: "failed",
                failure_message: "Workflow run was canceled or timed out"
              )
            end
          end
        end
      end
    end
  end

  def get_non_final_repo_tasks
    non_final_statuses = CodeqlVariantAnalysisRepoTask::NON_FINAL_STATUSES

    # Iterate over the non-final statuses and get the first 5000 repo tasks
    # for each status. We have separate queries for each status to make sure
    # the index we have on status and created_at is used.
    non_final_statuses.flat_map do |status|
      CodeqlVariantAnalysisRepoTask
        .where(status: status)
        .order(created_at: :asc)
        .limit(5_000)
    end
  end
end
