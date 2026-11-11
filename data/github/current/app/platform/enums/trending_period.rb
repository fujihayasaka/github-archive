# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class TrendingPeriod < Platform::Enums::Base
      description "Represents a time period during which repositories were trending."
      required_capabilities [:mobile_only_schema_mask]

      value "DAILY", "A time period covering the last day.", value: :daily
      value "WEEKLY", "A time period covering the last week.", value: :weekly
      value "MONTHLY", "A time period covering the last month.", value: :monthly
    end
  end
end
