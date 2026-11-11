# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SponsorsActivityPeriod < Platform::Enums::Base
      description "The possible time periods for which Sponsors activities can be requested."
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      value "DAY", "The previous calendar day.", value: :day
      value "WEEK", "The previous seven days.", value: :week
      value "MONTH", "The previous thirty days.", value: :month
      value "ALL", "Don't restrict the activity to any date range, include all activity.", value: :alltime
    end
  end
end
