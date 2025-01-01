# typed: strict
# frozen_string_literal: true

module Actions
  class LargerRunners::LargerRunnerJobsListComponent < ApplicationComponent
    sig do
      params(
        larger_runner: Actions::LargerRunner,
        check_runs: T::Array[CheckRun]
      ).void
    end
    def initialize(larger_runner: Actions::LargerRunner.new, check_runs: [])
      @larger_runner = larger_runner
      @check_runs = check_runs
    end
  end
end
