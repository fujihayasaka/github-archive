# typed: true
# frozen_string_literal: true

module Platform
  module Scalars
    class MobilePushScheduleTime < Platform::Scalars::Base
      description "A string representing the time of day with format HH:MM. eg. 00:00...23:59"

      def self.coerce_input(value, context)
        ::Time.strptime(value, "%H:%M")

        value
      rescue ArgumentError, ::TypeError
        nil
      end

      def self.coerce_result(value, context)
        value.to_s
      end
    end
  end
end
