# typed: strict
# frozen_string_literal: true

module Actions
  class LargerRunners::LargerRunnerJobsUsageComponent < ApplicationComponent
    sig do
      params(
        larger_runner: Actions::LargerRunner,
        runner_group: T.nilable(Actions::RunnerGroup),
        check_runs: T::Array[CheckRun]
      ).void
    end
    def initialize(larger_runner: Actions::LargerRunner.new, runner_group: nil, check_runs: [])
      @larger_runner = larger_runner
      @runner_group = runner_group
      @check_runs = check_runs
    end

    sig { returns(Integer) }
    def total_active_jobs
      if @check_runs.respond_to?(:total_entries)
        T.unsafe(@check_runs).total_entries
      else
        @check_runs.count
      end
    end

    sig { returns(Integer) }
    def total_unavailable_jobs
      @larger_runner.unavailable_runner_count || 0
    end

    sig { returns(Integer) }
    def total_runners_limit
      @larger_runner.maximum_runners
    end

    sig { returns(Integer) }
    def percentage
      total_runners_limit > 0 ? (total_active_jobs * 100) / total_runners_limit : 0
    end

    sig { returns(Integer) }
    def unavailable_percentage
      total_runners_limit > 0 ? (total_unavailable_jobs * 100) / total_runners_limit : 0
    end
  end
end
