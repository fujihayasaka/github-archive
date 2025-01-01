# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CvssSeverities < Platform::Objects::Base
      feature_flag :advisory_db_cvss_v4

      description "The Common Vulnerability Scoring System"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, calendar_week)
        # Access to this object is managed by its parent SecurityAdvisory.
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # Access to this object is managed by its parent SecurityAdvisory.
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      field :cvss_v3, Objects::CVSS, "The CVSS v3 severity associated with this advisory", null: true
      field :cvss_v4, Objects::CVSS, "The CVSS v4 severity associated with this advisory", null: true
    end
  end
end
