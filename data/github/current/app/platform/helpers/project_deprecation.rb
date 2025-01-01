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

      def self.raise_if_deprecation_enabled(viewer)
        return if GitHub.projects_classic_creation_enabled?

        return if viewer.feature_flag_enabled?(:memex_bypass_projects_classic_deprecation_rules, default: false)

        raise Platform::Errors::NotFound, "Projects (classic) creation is disabled for this resource"
      end

      # Raises a `NotFound` error if the Projects (classic) APIs should no longer be available. Should automatically
      # return `false` for enterprise, and a flag will control the behavior in dotcom/Proxima.
      def self.ensure_api_availability(viewer, oauth_app = nil, user_agent = nil)
        return if ProjectsClassicSunset.graphql_api_enabled?(viewer)

        if should_allow_projects_classic_request?(viewer, oauth_app, user_agent)
          yield if block_given?
          return
        end

        raise Errors::NotFound.new "#{Notice[:reason]}"
      end

      sig { params(viewer: T.nilable(User), oauth_app: T.untyped, user_agent: T.nilable(String)).returns(T::Boolean) }
      def self.should_allow_projects_classic_request?(viewer, oauth_app, user_agent)
        # If feature flag is enabled, disable all bypass mechanisms entirely (CLI, privileged apps, etc.)
        if viewer
          return false if viewer.feature_flag_enabled?(:projects_classic_bypass_disabled, default: false)
        else
          # For global checks when no viewer is provided, check if flag is globally enabled
          return false if FeatureFlag.vexi.enabled?(:projects_classic_bypass_disabled, default: false)
        end

        return true if user_agent.present? && user_agent.start_with?("GitHub CLI")
        return true if oauth_app.present? && Apps::Privileged.capable?(:projects_classic_graphql_api_disabled, app: oauth_app)
        false
      end
    end
  end
end
