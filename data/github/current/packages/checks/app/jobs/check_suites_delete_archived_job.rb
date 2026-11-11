# typed: true
# frozen_string_literal: true

class CheckSuitesDeleteArchivedJob < ApplicationJob

  include GitHub::Tracing
  include ChecksJobUtility
  include Scientist

  DELETE_BATCH_SIZE = 50.freeze
  READ_BATCH_SIZE = 5000.freeze

  queue_as :check_suites_delete_archived
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  trace_method :perform
  trace_method :delete_check_suites_and_dependencies

  # Deletes a batch of check_suites between a start and end time (inclusive)
  def perform(updated_at_start:, updated_at_end:, concurrent_job_key:)
    raise ArgumentError, "updated_at_start must be provided." unless updated_at_start.present?
    raise ArgumentError, "updated_at_end must be provided." unless updated_at_end.present?
    raise ArgumentError, "concurrent_job_key must be provided." unless concurrent_job_key.present?

    lock! do
      delete_check_suites_and_dependencies(updated_at_start: updated_at_start, updated_at_end: updated_at_end, concurrent_job_key: concurrent_job_key)
    rescue ActiveRecord::RecordNotFound, StandardError => e # rubocop:todo Lint/RescueException
      Failbot.report(e)
      raise e
    end
  end

  private

  def lock!
    restraint = GitHub::Restraint.new
    lock_key = self.class.name
    max_concurrent_jobs = 40  # Maximum of 40 concurrent jobs
    lock_ttl = 5.minutes
    restraint.lock!(T.must(lock_key), max_concurrent_jobs, lock_ttl) do
      yield
    end
  rescue GitHub::Restraint::UnableToLock
    GitHub.dogstats.increment("checks.delete_archived_job.unable_to_lock", tags: ["job:checksuite"])
  end

  # Check Suites have a complex entity relationship. A detailed breakdown can be found here: https://thehub.github.com/epd/engineering/products-and-services/actions/architecture/actions-checks/
  # When deleting a check suite without callbacks, all related entities must be destroyed as well and any elastic search indexes must also be updated
  def delete_check_suites_and_dependencies(updated_at_start:, updated_at_end:, concurrent_job_key:)
    total_delete_count = 0

    loop do
      archived_check_suites_ready_for_deletion = find_check_suites_to_delete(updated_at_start, updated_at_end)
      break if archived_check_suites_ready_for_deletion.empty?

      repo_id_pairs = group_by_repository_id(archived_check_suites_ready_for_deletion)
      repo_id_pairs.each do |repository_id, archived_check_suite_ids|

        delete_artifacts(repository_id, archived_check_suite_ids)
        delete_check_suite_level_annotations(repository_id, archived_check_suite_ids)
        delete_check_runs_and_check_run_annotations_and_workflow_job_runs(repository_id, archived_check_suite_ids)
        delete_workflow_runs_and_workflow_run_executions(repository_id, archived_check_suite_ids)

        batch_delete_count = delete_check_suites(repository_id, archived_check_suite_ids)
        total_delete_count = total_delete_count + batch_delete_count
      end
    end

    GitHub.dogstats.count("checks.delete_archived_job.deleted", total_delete_count, tags: ["model:checksuite"])

    clear_concurrency_key_for_batch(concurrent_job_key)
  end

  # Intentionally cross shard, long term with per shard DB connections this can be changed
  def find_check_suites_to_delete(updated_at_start, updated_at_end)
    CheckSuite
      .from("check_suites FORCE INDEX(index_check_suites_on_is_archived_updated_at)")
      .where("is_archived = true")
      .where("updated_at between :updated_at_start AND :updated_at_end", updated_at_start: updated_at_start, updated_at_end: updated_at_end)
      .where("updated_at <= ?", delete_archived_threshold_days.ago)
      .order(id: :asc)
      .limit(READ_BATCH_SIZE)
      .pluck(:repository_id, :id)
  end

  # There is no upper limit on the number of artifacts a check suite can have so the deletion must be done in batches
  def delete_artifacts(repository_id, check_suite_ids)
    loop do
      artifacts_to_delete =  Artifact
        .where(repository_id: repository_id, check_suite_id: check_suite_ids)
        .limit(READ_BATCH_SIZE)
        .pluck(:id)

      break if artifacts_to_delete.empty?

      ActiveRecord::Base.connected_to(role: :writing) do
        artifacts_to_delete.in_groups_of(DELETE_BATCH_SIZE) do |artifact_delete_id_batch|
          Artifact.throttle do
            # we don't invoke callbacks for artifact deletion. for both actions service and results backend, they will
            # handle the blob storage cleanup independently.
            Artifact.where(repository_id: repository_id, id: artifact_delete_id_batch).delete_all
          end
        end
      end
    end
  end

  # Third Party check suites can have up to 1000 check runs per check suite so batched iteration is needed for check run deletion
  # WorkflowJobRuns have a 1:1 relationship with check runs so we can delete them with the same batch of check run IDs
  def delete_check_runs_and_check_run_annotations_and_workflow_job_runs(repository_id, check_suite_ids)
    loop do
      check_runs_to_delete = Checks.domain.check_runs.ids_for_suite_ids(repository_id:, check_suite_ids:, limit: READ_BATCH_SIZE)

      break if check_runs_to_delete.empty?

      delete_check_run_level_annotations(repository_id, check_runs_to_delete)

      # check step deletion is handled by check_steps_delete_job so no need to worry about that here

      ActiveRecord::Base.connected_to(role: :writing) do
        check_runs_to_delete.in_groups_of(DELETE_BATCH_SIZE) do |check_runs_delete_batch|
          Actions::WorkflowJobRun.throttle do
            Actions::WorkflowJobRun.where(repository_id: repository_id, check_run_id: check_runs_delete_batch).delete_all
          end
          Checks.domain.check_runs.delete_for_ids(repository_id: repository_id, ids: check_runs_delete_batch)
        end
      end
    end
  end

  # There is no upper limit on the number of annotations a check run run can have so deletion must be done in batches
  def delete_check_run_level_annotations(repository_id, check_run_ids)
    loop do
      check_run_annotations_to_delete = CheckAnnotation
        .where(repository_id: repository_id, check_run_id: check_run_ids)
        .limit(READ_BATCH_SIZE)
        .pluck(:id)

      break if check_run_annotations_to_delete.empty?

      ActiveRecord::Base.connected_to(role: :writing) do
        check_run_annotations_to_delete.in_groups_of(DELETE_BATCH_SIZE) do |cr_annotation_delete_batch|
          CheckAnnotation.throttle do
            CheckAnnotation.where(repository_id: repository_id, id: cr_annotation_delete_batch).delete_all
          end
        end
      end
    end
  end

  # There is no upper limit on the number of annotations that can be tied to check suites. Check Suite annotations are Actions only
  # and usually there is at most one per check suite but to be safe we're going delete in batches
  def delete_check_suite_level_annotations(repository_id, check_suite_ids)
    loop do
      check_suite_annotations_to_delete = CheckAnnotation
        .where(repository_id: repository_id, check_suite_id: check_suite_ids)
        .limit(READ_BATCH_SIZE)
        .pluck(:id)

      break if check_suite_annotations_to_delete.empty?

      ActiveRecord::Base.connected_to(role: :writing) do
        check_suite_annotations_to_delete.in_groups_of(DELETE_BATCH_SIZE) do |cs_annotation_delete_batch|
          CheckAnnotation.throttle do
            CheckAnnotation.where(repository_id: repository_id, id: cs_annotation_delete_batch).delete_all
          end
        end
      end
    end
  end

  # Workflow runs have a 1:1 relationship with check suites so we don't have to worry about smaller batches. Limited to the earlier READ_BATCH_SIZE
  # Workflow run executions have a 1:many relationship so there may be large batches of executions within a batch of workflow runs to delete
  def delete_workflow_runs_and_workflow_run_executions(repository_id, check_suite_ids)
    workflow_runs_to_delete = Actions::WorkflowRun
      .where(repository_id: repository_id, check_suite_id: check_suite_ids)
      .pluck(:id, :check_suite_id)

    workflow_runs_ids_to_delete = workflow_runs_to_delete.map(&:first)
    workflow_run_id_to_check_suite_id = workflow_runs_to_delete.to_h

    loop do
      executions_to_delete = Actions::WorkflowRunExecution
        .where(repository_id: repository_id, workflow_run_id: workflow_runs_ids_to_delete)
        .limit(READ_BATCH_SIZE)
        .pluck(:id, :workflow_run_id, :external_id)
        .map do |id, workflow_run_id, external_id|
          {
            id: id,
            workflow_run_id: workflow_run_id,
            check_suite_id: workflow_run_id_to_check_suite_id[workflow_run_id],
            external_id: external_id,
          }
        end

      break if executions_to_delete.empty?

      ActiveRecord::Base.connected_to(role: :writing) do
        executions_to_delete.map { |e| e[:id] }.in_groups_of(DELETE_BATCH_SIZE) do |execution_id_batch|
          Actions::WorkflowRunExecution.throttle do
            Actions::WorkflowRunExecution.where(repository_id: repository_id, id: execution_id_batch).delete_all
          end
        end
      end

      emit_workflow_run_deleted(repository_id, executions_to_delete)
    end

    remove_workflow_runs_from_elastic_search(repository_id, workflow_runs_ids_to_delete)

    ActiveRecord::Base.connected_to(role: :writing) do
      workflow_runs_ids_to_delete.in_groups_of(DELETE_BATCH_SIZE) do |workflow_run_id_batch|
        Actions::WorkflowRun.throttle do
          Actions::WorkflowRun.where(repository_id: repository_id, id: workflow_run_id_batch).delete_all
        end
      end
    end
  end

  def delete_check_suites(repository_id, check_suite_ids)
    check_suite_delete_count = 0

    ActiveRecord::Base.connected_to(role: :writing) do
      check_suite_ids.in_groups_of(DELETE_BATCH_SIZE) do |check_suite_id_batch|
        deleted_count = CheckSuite.throttle do
          CheckSuite.where(repository_id: repository_id, id: check_suite_id_batch).delete_all
        end
        check_suite_delete_count = check_suite_delete_count + deleted_count
      end
    end

    check_suite_delete_count
  end

  def remove_workflow_runs_from_elastic_search(repository_id, workflow_run_ids)
    # When deleting a workflow run through callbacks in workflow_run.rb  synchronize_search_index is called which ends up queing RemoveFromSearchIndexJob
    # RemoveFromSearchIndexJob gets queued onto github-sloworker. See https://app.datadoghq.com/dashboard/u5j-g26-scy/github-jobs?tpl_var_app-role%5B0%5D=github-slowworker
    jobs = workflow_run_ids.map { |workflow_run_id| RemoveFromSearchIndexJob.new("workflow_run", workflow_run_id, repository_id) }
    ActiveJob.perform_all_later(jobs)

    GitHub.dogstats.count("checks.delete_archived_job.enqueued_remove_from_search_index_jobs", jobs.count)
  end

  sig do
    params(
      repository_id: Integer,
      executions: T::Array[
        {
          id: Integer,
          workflow_run_id: Integer,
          check_suite_id: Integer,
          external_id: String,
        }
      ]
    ).void
  end
  def emit_workflow_run_deleted(repository_id, executions)
    executions.each do |execution|
      Actions::WorkflowRun.emit_workflow_run_deleted(
        repository_id: repository_id,
        check_suite_id: execution[:check_suite_id],
        workflow_run_id: execution[:workflow_run_id],
        execution_external_id: execution[:external_id],
      )
    end
  end
end
