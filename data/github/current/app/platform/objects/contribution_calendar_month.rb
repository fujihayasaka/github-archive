# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ContributionCalendarMonth < Platform::Objects::Base
      description "A month of contributions in a user's contribution graph."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, calendar_month)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end


      scopeless_tokens_as_minimum

      field :name, String, null: false, description: "The name of the month."

      field :year, Integer, null: false, description: "The year the month occurred in."

      field :total_weeks, Integer, null: false, description: "How many weeks started in this month."

      field :first_day, Scalars::Date, null: false,
        description: "The date of the first day of this month."
    end
  end
end
