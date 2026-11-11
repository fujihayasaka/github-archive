# typed: true
# frozen_string_literal: true

module Actions
  class LargerRunners::LargerRunnerTitleWithIconComponent < ApplicationComponent
    def initialize(larger_runner:, owner_settings:)
      @larger_runner = larger_runner
      @owner_settings = owner_settings
    end

    def runner_state_scheme
      return :attention if runner_action_needed?
      case @larger_runner.state
      when :Ready
        :success
      when :Provisioning
        :warning
      when :Deleting
        :danger
      when :ShutdownBilling, :ShutdownSpammy, :ShutdownNetwork
        :danger
      else
        :primary
      end
    end

    def runner_state
      return "Shutdown" if @larger_runner.state&.match("^Shutdown")
      return "Action needed" if runner_action_needed?
      @larger_runner.state
    end

    def runner_action_needed?
      @larger_runner.error_code.present?
    end
  end
end
