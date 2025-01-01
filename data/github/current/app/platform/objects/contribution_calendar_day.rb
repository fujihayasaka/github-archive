# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ContributionCalendarDay < Platform::Objects::Base
      description "Represents a single day of contributions on GitHub by a user."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, calendar_square)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      field :date, Scalars::Date, description: "The day this square represents.", null: false

      field :contribution_count, Integer, method: :count,
        description: "How many contributions were made by the user on this day.", null: false

      field :contribution_level, Enums::ContributionLevel, method: :level, null: false,
        description: "Indication of contributions, relative to other days. Can be used to indicate which color to represent this day on a calendar."

      field :color, String, null: false,
        description: "The hex color code that represents how many contributions were made on this day compared to others in the calendar."

      field :weekday, Integer, null: false,
        description: "A number representing which day of the week this square represents, e.g., 1 is Monday."
    end
  end
end
