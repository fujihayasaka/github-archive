# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ContributionCalendarWeek < Platform::Objects::Base
      description "A week of contributions in a user's contribution graph."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, calendar_week)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      field :contribution_days, [ContributionCalendarDay], null: false,
        description: "The days of contributions in this week."

      field :first_day, Scalars::Date, null: false,
        description: "The date of the earliest square in this week."
    end
  end
end
