# typed: true
# frozen_string_literal: true

class FixBrokenWorkflowJobRunsJob < ApplicationJob
  include GitHub::Tracing
  include ChecksJobUtility

  queue_as :fix_broken_workflow_job_runs
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  trace_method :perform
  trace_method :fix_broken_workflow_job_runs

  exempt_from_tenant_context_requirement

  def perform(workflow_run_id)
    # we shouldn't have to worry about running this job on enterprise because the issue is caused by RAC replication lag
    return if GitHub.enterprise?

    fix_broken_workflow_job_runs(workflow_run_id)
  end

  private

  def fix_broken_workflow_job_runs(workflow_run_id)
    raise ArgumentError, "workflow_run_id must be provided." unless workflow_run_id.present?

    wr = Actions::WorkflowRun.find(workflow_run_id)
    wres = wr.workflow_run_executions

    cs = T.must(wr.check_suite)
    check_runs = cs.check_runs

    # Create a data structure that allows us to:
    # 1. access a specific check run based on its :name, which is consistent between check runs even if :id is different
    # 2. Using :name to find a subset of check runs, find a specific check run by :id
    # 3. Access the started_at and created_at times of the specific check run

    # Looks like this at the end, given we have the following example:
    # Check Run 1: name: "3a9a827b-19da-4c73-8f6e-ab95a5be2baf", id: "46747573475", created_at: "2025-07-17 14:40:35 UTC", started_at: "2025-07-17 14:40:35 UTC"
    # Check Run 2: name: "3a9a827b-19da-4c73-8f6e-ab95a5be2baf", id: "48472572652", created_at: "2025-07-18 14:40:35 UTC", started_at: "2025-07-17 14:40:35 UTC"
    # Check Run 3: name: "74c65d41-328f-4f8a-937e-0dd5c138d1da", id: "31372572652", created_at: "2025-07-18 15:41:35 UTC", started_at: "2025-07-18 15:45:27 UTC"
    #
    # Resulting Data Structure:
    # {
    #   "3a9a827b-19da-4c73-8f6e-ab95a5be2baf" => {
    #     46747573475 => { "created_at": "2025-07-17 14:40:35 UTC", "started_at": "2025-07-17 14:40:35 UTC" },
    #     48472572652 => { "created_at": "2025-07-18 14:40:35 UTC", "started_at": "2025-07-17 14:40:35 UTC" }
    #   },
    #   "74c65d41-328f-4f8a-937e-0dd5c138d1da" => {
    #     31372572652 => { "created_at": "2025-07-18 15:41:35 UTC", "started_at": "2025-07-18 15:45:27 UTC" }
    #   }
    # }
    check_run_references = check_runs.each_with_object({}) do |cr, hash|
      name = cr[:name]
      id = cr[:id]
      hash[name] ||= {}
      hash[name][id] = {
        "created_at": cr[:created_at],
        "started_at": cr[:started_at]
      }
    end

    # Map UNIX timestamp of workflow run executions to the executions themselves
    created_at_to_wre = wres.map { |wre| [wre.created_at.utc.to_i, wre] }.to_h

    # Get broken workflow job runs
    broken_workflow_job_runs = wr.workflow_job_runs.where("original_workflow_run_execution_id IS NULL OR workflow_run_execution_id IS NULL")
    broken_workflow_job_runs.each do |bwjr|
      associated_check_run = T.must(check_runs.find { |cr| cr.id == bwjr.check_run_id })
      check_run_name = T.must(associated_check_run.name)
      check_run_id = T.must(associated_check_run.id)

      cr_entry = T.must(check_run_references[check_run_name])[check_run_id]
      cr_entry = T.must(cr_entry)

      # Do a binary search on created_at_to_wre in order to find the workflow run execution which was created
      # just before the check run was created. This tells us about the current run
      current_workflow_run_execution_timestamp = created_at_to_wre.keys.sort.reverse.bsearch { |t| t <= cr_entry[:created_at].utc.to_i }
      current_workflow_run_execution = created_at_to_wre[current_workflow_run_execution_timestamp]

      if current_workflow_run_execution.nil?
        GitHub.logger.info("workflow_run_execution unexpectedly nil while attempting repair", {
          "gh.actions.workflow_job_run.backend_id" => bwjr.id,
          "gh.actions.workflow_run.backend_id" => cs.external_id,
          "gh.actions.workflow_run_execution.backend_id" => workflow_run_id,
        })
        return
      end

      # In the partial rerun case original_workflow_run_execution_id != workflow_run_execution_id, we need to use the started_at
      # time on the check run to find the workflow run execution associated with the original attempt, again making
      # use of binary search to do so
      original_workflow_run_execution = current_workflow_run_execution
      if cr_entry[:created_at].utc.to_i > cr_entry[:started_at].utc.to_i
        original_workflow_run_execution_timestamp = created_at_to_wre.keys.sort.reverse.bsearch { |t| t <= cr_entry[:started_at].utc.to_i }
        original_workflow_run_execution = created_at_to_wre[original_workflow_run_execution_timestamp]
      end

      if original_workflow_run_execution.nil?
        GitHub.logger.info("workflow_run_execution unexpectedly nil while attempting repair", {
          "gh.actions.workflow_job_run.backend_id" => bwjr.id,
          "gh.actions.workflow_run.backend_id" => cs.external_id,
          "gh.actions.workflow_run_execution.backend_id" => workflow_run_id,
        })
        return
      end

      # Now, update the broken workflow job run with the right information
      with_write do
        bwjr.update(workflow_run_execution_id: current_workflow_run_execution.id, original_workflow_run_execution_id: original_workflow_run_execution.id)
      end

      # Increment the stats and log
      GitHub.dogstats.increment("actions.workflow_job_run.repaired_broken_workflow_job_runs", tags: ["case:complex"])
      GitHub.logger.info("repaired broken workflow job run for workflow run", {
        "gh.actions.workflow_job_run.backend_id" => bwjr.id,
        "gh.actions.workflow_run.backend_id" => cs.external_id,
        "gh.actions.workflow_run_execution.backend_id" => workflow_run_id,
      })
    end
  end
end
