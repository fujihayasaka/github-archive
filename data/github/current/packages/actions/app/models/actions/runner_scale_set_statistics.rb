# typed: true
# frozen_string_literal: true

class Actions::RunnerScaleSetStatistics
  attr_reader :total_available_jobs, :total_acquired_jobs, :total_assigned_jobs, :total_running_jobs,
    :total_registered_runners, :total_busy_runners, :total_idle_runners

  def initialize(
    total_available_jobs:,
    total_acquired_jobs:,
    total_assigned_jobs:,
    total_running_jobs:,
    total_registered_runners:,
    total_busy_runners:,
    total_idle_runners:
  )
    @total_available_jobs = total_available_jobs
    @total_acquired_jobs = total_acquired_jobs
    @total_assigned_jobs = total_assigned_jobs
    @total_running_jobs = total_running_jobs
    @total_registered_runners = total_registered_runners
    @total_busy_runners = total_busy_runners
    @total_idle_runners = total_idle_runners
  end

  def self.from_rpc_object(entity, skip_statistics: false)
    if skip_statistics && entity.nil?
      # When statistics are intentionally skipped and the RPC omits the statistics
      # message, return a safe placeholder object instead of nil so callers that
      # assume statistics are present do not raise at runtime.
      return new(
        total_available_jobs: 0,
        total_acquired_jobs: 0,
        total_assigned_jobs: 0,
        total_running_jobs: 0,
        total_registered_runners: 0,
        total_busy_runners: 0,
        total_idle_runners: 0
      )
    end

    return nil if entity.nil?

    new(
      total_available_jobs: entity.total_available_jobs,
      total_acquired_jobs: entity.total_acquired_jobs,
      total_assigned_jobs: entity.total_assigned_jobs,
      total_running_jobs: entity.total_running_jobs,
      total_registered_runners: entity.total_registered_runners,
      total_busy_runners: entity.total_busy_runners,
      total_idle_runners: entity.total_idle_runners
    )
  end
end
