# typed: true
# frozen_string_literal: true

require "github/timeout_and_measure"
require "github/pages/management/delegate"
require "github/pages/management/evacuate"

class DpagesEvacuationSchedulerJob < ApplicationJob
  # This job is a background maintenance task that works across a stamp.
  exempt_from_tenant_context_requirement

  queue_as :dpages_evacuations_scheduler

  locked_by timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  include GitHub::TimeoutAndMeasure

  # Run for at most two minutes so the user doesn't need to intervene to stop
  # the job manually.
  def self.max_execution_time
    2.minutes
  end

  # Run every interval, schedules jobs_per_interval maintenance jobs to run.
  def perform(*args)
    sites_enqueued = 0

    timeout_and_measure(self.class.max_execution_time.to_i, "pages.dpages_evacuations.scheduler") do
      evacuating_hosts = GitHub::Pages::Management::Evacuate.evacuating_hosts

      evacuating_hosts.each do |host|
        command = GitHub::Pages::Management::Evacuate.new(
          host: host,
          delegate: GitHub::Pages::Management::Delegate.new(logger: GitHub::Logger),
        )
        command.sites_to_evacuate(limit: GitHub.dpages_evacuations_scheduler_batch_size).each do |(page_id, page_deployment_id)|
          break if sites_enqueued >= GitHub.dpages_evacuations_scheduler_batch_size

          DpagesEvacuateSiteJob.perform_later(page_id, page_deployment_id, host)
          sites_enqueued += 1
        end
      end
    end
  end
end
