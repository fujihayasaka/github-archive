# typed: true
# frozen_string_literal: true
module Actions
  class LargerRunners::LargerRunnerPublicIpBannerComponent < ApplicationComponent
    include ::Actions::LargerRunnersHelper
    include ResilienceHelper

    def initialize(larger_runner:, owner:)
      @larger_runner = larger_runner
      @owner = owner
    end

    def should_disable_public_ip_from_downgrade
      return false if public_ip_graceful_period.nil?

      @larger_runner.is_public_ip_enabled && !is_public_ip_allowed_for_entity?(@owner)
    end

    def should_disable_public_ip_from_non_use_limit
      return false if max_non_used_days.nil?

      @larger_runner.is_public_ip_enabled && is_over_non_used_limit?
    end

    def is_over_non_used_limit?
      runner_last_used_days_ago >= max_non_used_days
    end

    def runner_last_used_days_ago
      last_active_on = @larger_runner.last_active_on.to_datetime
      today = DateTime.now.new_offset.midnight # new_offset converts time to UTC
      (today - last_active_on).to_i
    end

    memoize def public_ip_graceful_period
      with_database_error_fallback(fallback: nil) do
        Actions::LargerRunner::PublicIPSettings.graceful_period_for(@owner)
      end
    end

    memoize def max_non_used_days
      with_database_error_fallback(fallback: nil) do
        Actions::LargerRunner::PublicIPSettings.max_non_used_days_for(@owner)
      end
    end
  end
end
