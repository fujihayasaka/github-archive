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

  def self.from_rpc_object(entity)
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
