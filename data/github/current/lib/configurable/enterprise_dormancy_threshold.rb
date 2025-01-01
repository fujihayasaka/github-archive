# typed: true
# frozen_string_literal: true

module Configurable
  module EnterpriseDormancyThreshold
    extend T::Helpers

    requires_ancestor { Configurable }

    DORMANCY_THRESHOLD_DAYS_KEY = "enterprise_dormancy_threshold_days".freeze
    DEFAULT_DORMANCY_THRESHOLD_DAYS = 90
    VALID_DORMANCY_THRESHOLD_DAYS_VALUES = [
      30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330, 360
    ].freeze

    def set_enterprise_dormancy_threshold_days(days, actor)
      return false unless VALID_DORMANCY_THRESHOLD_DAYS_VALUES.include?(days)

      config.set(DORMANCY_THRESHOLD_DAYS_KEY, days, actor)
      true
    end

    def enterprise_dormancy_threshold_days
      days = config.get(DORMANCY_THRESHOLD_DAYS_KEY) || DEFAULT_DORMANCY_THRESHOLD_DAYS
      days.to_i
    end

    def enterprise_dormancy_threshold
      enterprise_dormancy_threshold_days.days
    end
  end
end
