# typed: true
# frozen_string_literal: true

module Codespaces
  class RetentionPeriodComponent < ApplicationComponent
    def initialize(entity:, update_retention_period_path:)
      @entity = entity
      @update_retention_period_path = update_retention_period_path
    end

    def description
      "Inactive codespaces are automatically deleted 30 days after the last time they were stopped. A shorter retention period can be set, and will apply to all codespaces created going forward."
    end

    memoize def upper_limit
      Codespace::MAX_RETENTION_PERIOD.minutes.in_days.to_i
    end

    def lower_limit
      0
    end

    def value
      @entity.codespace_default_retention_period
    end

    def value_in_days
      return nil unless value
      value.minutes.in_days.to_i
    end

    def upper_limit_error
      "Retention period must be #{upper_limit} days or less."
    end

    def lower_limit_error
      "Retention period must be between #{lower_limit} and #{upper_limit} days."
    end
  end
end
