# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ContributionCalendar < Platform::Objects::Base
      description "A calendar of contributions made on GitHub by a user."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, contrib_calendar)
        if contrib_calendar.is_a?(Contribution::CalendarSample)
          true
        else
          contrib_calendar.viewer.nil? || permission.viewer == contrib_calendar.viewer
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        if object.is_a?(Contribution::CalendarSample)
          true
        else
          object.viewer.nil? || object.viewer == permission.viewer
        end
      end

      scopeless_tokens_as_minimum

      field :is_halloween, Boolean, null: false, method: :halloween?,
        description: "Determine if the color set was chosen because it's currently Halloween."

      url_fields description: "The HTTP URL for the user's contributions graph.",
        visibility: :under_development do |calendar|
          calendar.async_url
        end

      field :colors, [String], null: false,
        description: "A list of hex color codes used in this calendar. The darker the " \
                     "color, the more contributions it represents."

      field :total_contributions, Integer,
        description: "The count of total contributions in the calendar.", null: false

      field :weeks, [ContributionCalendarWeek], null: false,
        description: "A list of the weeks of contributions in this calendar."

      def weeks
        ArrayWrapper.new(@object.weeks)
      end

      # 12 months in a year
      field :months, [ContributionCalendarMonth], complexity: 12, null: false,
        description: "A list of the months of contributions in this calendar."

      def months
        ArrayWrapper.new(@object.months)
      end
    end
  end
end
