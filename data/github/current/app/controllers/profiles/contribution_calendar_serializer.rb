# typed: true
# frozen_string_literal: true

module Profiles
  # colocated serializer used only by ContributionCalendarsController
  class ContributionCalendarSerializer
    SCHEMA_VERSION = "v2" # Bump when payload shape changes in a non-backward-compatible way
    def initialize(calendar:)
      @calendar = calendar
    end

    def as_json(*)
      {
        schema: SCHEMA_VERSION,
        generated_at: Time.current.utc.iso8601,
        from: @calendar.from.iso8601,
        to: @calendar.to.iso8601,
        range_days: (@calendar.to - @calendar.from).to_i + 1,
        total_contributions: @calendar.total_contributions,
        private_contributions_included: private_contributions_included?,
        colors_full: [Contribution::Calendar::DEFAULT_ZERO_COLOR] + @calendar.colors,
        weeks: weeks_payload,
        months: months_payload,
      }
    end

    private

    def weeks_payload
      @calendar.weeks.map.with_index do |week, idx|
        {
          index: idx,
          first_day: week.first_day&.iso8601,
          contribution_days: week.contribution_days.map do |day|
            {
              weekday: day.weekday,
              count: day.count,
              level: day.level,
            }
          end,
        }
      end
    end

    def months_payload
      @calendar.months.map do |month|
        {
          month: month.first_day&.strftime("%Y-%m"),
          total_weeks: month.total_weeks,
        }
      end
    end

    def private_contributions_included?
      user = @calendar.user
      user.profile_settings.show_private_contribution_count? && @calendar.organization_id.nil?
    end
  end
end
