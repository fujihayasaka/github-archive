# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class DeleteOldCheckRuns < ApplicationJob
  queue_as :delete_old_check_runs

  MAX_CHECK_RUNS_PER_JOB = 100
  retry_on_dirty_exit

  before_enqueue do |job|
    check_run_ids = [job.arguments[0]].flatten
    # Don't log if above the max as it will be split up anyways
    if check_run_ids.size <= MAX_CHECK_RUNS_PER_JOB
      GitHub.dogstats.count("check_runs.delete_old_runs", check_run_ids.size)
    end
  end

  def self.perform_later_in_groups(ids, repository_id:)
    ids.in_groups_of(MAX_CHECK_RUNS_PER_JOB, false) do |group|
      DeleteOldCheckRuns.perform_later(group, repository_id: repository_id)
    end
  end

  def perform(check_run_ids, repository_id:)
    all_ids = [check_run_ids].flatten

    # We want to split this up to a MAX number of check runs per job to avoid
    # deleting too many jobs at once and invoking too many callbacks. To do this
    # we split the ids array up and process individual groups.
    # It is recommended to call `perform_later_in_groups` instead of `perform_later` unless you know
    # you have MAX_CHECK_RUNS_PER_JOB or less ids
    if all_ids.size > MAX_CHECK_RUNS_PER_JOB
      all_ids.in_groups_of(MAX_CHECK_RUNS_PER_JOB, false) do |group|
        DeleteOldCheckRuns.perform_later(group, repository_id: repository_id)
      end
      return
    end

    check_runs = CheckRun.where(id: all_ids, repository_id: repository_id).limit(MAX_CHECK_RUNS_PER_JOB)

    if check_run_ids.size - check_runs.size > 0
      GitHub.logger.info("Skipping the following checkruns that do not exist", {
        "code.namespace" => self.class.name,
        "code.function" => "perform",
        "gh.repo.id" => repository_id,
        "gh.check_runs.missing_ids" => all_ids - check_runs.map(&:id)
      })
    end

    check_runs.each do |check_run|
      CheckRun.throttle_writes do
        check_run.destroy
      end
    end
  end
end
