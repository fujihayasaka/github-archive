# typed: true
# frozen_string_literal: true

module Actions
  class RunnerScaleSets::RunnerScaleSetStatisticsComponent < ApplicationComponent
    delegate :total_available_jobs, :total_assigned_jobs, :total_running_jobs, :total_busy_runners, :total_idle_runners, to: :@statistics

    def initialize(scale_set:)
      @statistics = scale_set.statistics
    end
  end
end
