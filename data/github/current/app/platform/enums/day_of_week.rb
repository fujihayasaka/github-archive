# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class DayOfWeek < Platform::Enums::Base
      description "Days of the week."
      mobile_only true

      value "MONDAY", "Monday", value: "monday"
      value "TUESDAY", "Tuesday", value: "tuesday"
      value "WEDNESDAY", "Wednesday", value: "wednesday"
      value "THURSDAY", "Thursday", value: "thursday"
      value "FRIDAY", "Friday", value: "friday"
      value "SATURDAY", "Saturday", value: "saturday"
      value "SUNDAY", "Sunday", value: "sunday"
    end
  end
end
