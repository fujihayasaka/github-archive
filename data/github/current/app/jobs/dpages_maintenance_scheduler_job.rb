# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

require "github/timeout_and_measure"
require "github/pages/management/delegate"
require "github/pages/management/repair"

class DpagesMaintenanceSchedulerJob < ApplicationJob
  # This job is a background maintenance task that works across a stamp.
  exempt_from_tenant_context_requirement

  queue_as :dpages_maintenance_scheduler

  include GitHub::TimeoutAndMeasure

  # Only one may run at any given time. Locked based on the uniqueness of args.
  locked_by timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  attr_reader :delegate, :args

  def perform(*args, delegate: nil)
    @delegate = delegate || GitHub::Pages::Management::Delegate.new
    @args = args

    timeout_and_measure(GitHub.dpages_maintenance_scheduler_maximum_execution_time.to_i, "pages.dpages_maintenance.scheduler") do
      repairable_unhealthy_pages_replica_counts do |repl|
        if GitHub.enterprise? || GitHub.flipper[:pages_azure_dfs_host].enabled?
          DpagesRepairSiteJob.perform_later(repl.page_id, repl.page_deployment_id, repl.voting)
        end
      end
    end
  end

  def repairable_unhealthy_pages_replica_counts
    GitHub::Pages::Management::Repair.new(delegate: delegate)
      .repairable_unhealthy_pages_replica_counts(limit: GitHub.dpages_maintenance_scheduler_batch_size) do |repl|
        yield repl
      end
  end
end
