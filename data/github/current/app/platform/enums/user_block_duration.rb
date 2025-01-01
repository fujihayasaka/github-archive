# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class UserBlockDuration < Platform::Enums::Base
      description "The possible durations that a user can be blocked for."

      value "ONE_DAY", "The user was blocked for 1 day", value: 1
      value "THREE_DAYS", "The user was blocked for 3 days", value: 3
      value "ONE_WEEK", "The user was blocked for 7 days", value: 7
      value "ONE_MONTH", "The user was blocked for 30 days", value: 30
      value "PERMANENT", "The user was blocked permanently", value: 0
    end
  end
end
