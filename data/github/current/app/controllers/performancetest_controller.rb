# typed: true
# frozen_string_literal: true

class PerformancetestController < ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:show]

  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  def show
    return head :not_found unless current_user&.site_admin?

    timer = Timer.start

    scenario = params.fetch("scenario", "cpu")
    case scenario
    when "minor"
      minor
    when "major"
      major
    when "cpu_simple"
      cpu_simple
    when "memory_simple"
      memory_simple
    else
      cpu
    end

    timer.stop

    render status: 200, json: {
      scenario: scenario,
      elapsed_monotonic_ms: timer.elapsed_ms,
      elapsed_process_cpu_ms: timer.elapsed_cpu_ms,
      elapsed_thread_cpu_ms: timer.elapsed_thread_cpu_ms,
    }
  end

  private

  def cpu_simple
    1 + 2
  end

  def memory_simple
    Object.new
  end

  def cpu
    10_000_000.times { 1 + 2 }
  end

  def minor
    3_000_000.times { Object.new }
  end

  $omega_performance_test = []
  def major
    3_000_000.times { $omega_performance_test << Object.new }
    $omega_performance_test = []
  end
end
