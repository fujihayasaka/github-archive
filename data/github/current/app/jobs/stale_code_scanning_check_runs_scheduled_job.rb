# typed: true
# frozen_string_literal: true

class StaleCodeScanningCheckRunsScheduledJob < ApplicationJob
  queue_as :code_scanning

  # this is a background job that finds check runs across tenants that have not resolved successfully
  exempt_from_tenant_context_requirement

  schedule interval: 1.hour

  before_perform do |job|
    Failbot.push(job: job.class.name)
  end

  retry_on_dirty_exit

  def self.stale_check_runs
    check_suite_query = CheckSuite.
      for_app_id(Apps::Privileged.integration_id(:code_scanning)).
      where(conclusion: nil).
      where("check_suites.updated_at < NOW() - INTERVAL 1 HOUR")
    CheckRun.
      joins("INNER JOIN check_suites ON check_suites.id = check_runs.check_suite_id").
      where("check_runs.repository_id = check_suites.repository_id").
      where(conclusion: nil).
      merge(check_suite_query).
      preload(check_suite: :repository)
  end

  # Public: Finds stale code scanning check runs to clean up.
  #
  # limit - The number of check runs to process per job run
  def perform(limit: 1000)
    check_runs = StaleCodeScanningCheckRunsScheduledJob.stale_check_runs.limit(limit)

    check_runs_by_repository = check_runs.group_by { |cr| cr.check_suite&.repository }

    check_runs_by_repository.each do |repository, check_runs|
      if repository.blank?
        with_primaries [ApplicationRecord::RepositoriesActionsChecks] do
          check_runs.each do |check_run|
            # We use update_columns here because the callbacks on CheckRun
            # fail with a nil repository.
            check_run.update_columns(title: "Unable to find repository", conclusion: "failure")
          end
        end
        next
      end

      # If the checkrun has been stale for more than 48h, resolve it as failed.
      # We probably retried this already several times and there must be something
      # else preventing us from making progress
      skip_check_runs = []
      check_runs.each do |check_run|
        if check_run.updated_at < (Time.zone.now - 48.hours)
          skip_check_runs << check_run
        end
      end
      with_primaries [ApplicationRecord::RepositoriesActionsChecks] do
        skip_check_runs.each do |check_run|
          check_run.update(title: "Unexpected error", conclusion: "failure")
        end
      end
      GitHub.logger.info(
        "Skipping check_runs that were stale for too long",
        "code.namespace" => "StaleCodeScanningCheckRunsScheduledJob",
        "code.function" => "perform",
        "gh.repo.id" => repository.id,
        "gh.repo.name_with_owner" => repository.nwo,
        "gh.code_scanning.skip_check_runs" => skip_check_runs.map(&:id),
      )
      check_runs -= skip_check_runs

      # Tools that are not CodeQL are more prone to stale check runs, as they might be submitting invalid SARIF.
      # We track the counters separately for CodeQL
      codeql_count = check_runs.count { |c| c.name == "CodeQL" }

      GitHub.dogstats.count("code_scanning.stale_check_runs", codeql_count, tags: ["tool:CodeQL"])
      GitHub.dogstats.count("code_scanning.stale_check_runs", check_runs.count - codeql_count, tags: ["tool:other"])

      check_run_ids = check_runs.map(&:id)
      check_run_refs = check_runs.map do |check_run|
        check_run.check_suite.head_branch
      end
      check_run_shas = check_runs.map do |check_run|
        check_run.check_suite.head_sha
      end
      check_run_tools = check_runs.map(&:name)
      GitHub.logger.info(
        "Refreshing stale check runs",
        "code.namespace" => "StaleCodeScanningCheckRunsScheduledJob",
        "code.function" => "perform",
        "gh.repo.id" => repository.id,
        "gh.repo.nwo" => repository.nwo,
        "git.refs" => check_run_refs,
        "git.shas" => check_run_shas,
        "gh.check_run.ids" => check_run_ids,
        "gh.code_scanning.tools" => check_run_tools,
      )
      with_write do
        repository.refresh_code_scanning_status(check_run_ids: check_run_ids, refresh_reason: :staleness_check)
      end
    end
  end

end
