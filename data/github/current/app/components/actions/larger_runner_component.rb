# typed: strict
# frozen_string_literal: true

module Actions
  class LargerRunnerComponent < ApplicationComponent
    sig do
      params(
        larger_runner: LargerRunner,
        owner_settings: T.any(EnterpriseRunnersView, OrgRunnersView),
        check_runs: T::Array[CheckRun]
      ).void
    end
    def initialize(larger_runner:, owner_settings:, check_runs: [])
      @larger_runner = larger_runner
      @owner_settings = owner_settings
      @check_runs = check_runs
    end

    sig { returns(RunnerGroup) }
    def runner_group
      @larger_runner.runner_group(@owner_settings.settings_owner)
    end
  end
end
