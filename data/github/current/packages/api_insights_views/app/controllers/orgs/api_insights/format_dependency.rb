# typed: strict
# frozen_string_literal: true

module Orgs
  module ApiInsights
    module FormatDependency
      include ActionView::Helpers::NumberHelper

      VALUE_IN_SECONDS = T.let({
        m: 60,
        h: 3600,
        d: 86400,
      }.freeze, T::Hash[Symbol, Integer])

      DATE_LONG = "%B %d, %Y %-I:%M %p %Z"
      DATE_SHORT = "%b %-d %-I:%M %p"
      DATE_SHORT_WITH_TIMEZONE = "%b %-d %-I:%M %p %Z"
      TIME_ZONE = "%Z"

      sig { params(human_readable_duration: String).returns(Integer) }
      def human_readable_duration_to_seconds(human_readable_duration)
        base = human_readable_duration.to_i
        value_in_seconds = VALUE_IN_SECONDS[human_readable_duration.last.to_sym]
        value_in_seconds && base ? base * value_in_seconds : 86400
      end

      sig { params(count: Integer).returns(String) }
      def round_to_human(count)
        units = { thousand: "k", million: "m", billion: "b" }
        number_to_human(count, precision: 1, significant: false, units: units, format: "%n%u")
      end

      sig { params(time: Time, user: T.nilable(User), local_time: T::Boolean).returns(String) }
      def format_time_long(time:, user:, local_time:)
        if local_time
          return time.in_time_zone(user&.time_zone || Time.zone).strftime(DATE_LONG)
        end
        time.utc.strftime(DATE_LONG)
      end

      sig { params(time: Time, user: T.nilable(User), local_time: T::Boolean, with_time_zone: T::Boolean).returns(String) }
      def format_time_short(time:, user:, local_time:, with_time_zone: false)
        used_format = with_time_zone ? DATE_SHORT_WITH_TIMEZONE : DATE_SHORT
        if local_time
          return time.in_time_zone(user&.time_zone || Time.zone).strftime(used_format)
        end
        time.utc.strftime(used_format)
      end

      sig { params(user: T.nilable(User), local_time: T::Boolean).returns(String) }
      def get_time_zone_string(user:, local_time:)
        if local_time
          return Time.now.in_time_zone(user&.time_zone || Time.zone).strftime(TIME_ZONE)
        end
        "UTC"
      end
    end
  end
end
