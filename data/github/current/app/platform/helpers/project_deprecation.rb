# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    class ProjectDeprecation
      Notice = {
        start_date: Date.new(2024, 10, 1),
        reason: "Projects (classic) is being deprecated in favor of the new Projects experience, see: https://github.blog/changelog/2024-05-23-sunset-notice-projects-classic/.",
        superseded_by: nil,
        owner: "github/memex",
      }

      # Raises a `NotFound` error if the Projects (classic) APIs should no longer be available. Should automatically
      # return `false` for enterprise, and a flag will control the behavior in dotcom/Proxima.
      def self.ensure_api_availability(viewer, oauth_app = nil, user_agent = nil)
        return if ProjectsClassicSunset.graphql_api_enabled?(viewer)

        raise Errors::NotFound.new "#{Notice[:reason]}"
      end
    end
  end
end
