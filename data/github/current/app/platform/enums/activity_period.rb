# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class ActivityPeriod < Platform::Enums::Base
      description "The time period when the activity was performed."

      value "DAY", "Past 24 hours.", value: "day"
      value "WEEK", "Past 7 days (168 hours).", value: "week"
      value "MONTH", "Past month (approx. 30 days).", value: "month"
      value "QUARTER", "Past quarter (3 months).", value: "quarter"
      value "YEAR", "Past year (approx. 365 days).", value: "year"
    end
  end
end
