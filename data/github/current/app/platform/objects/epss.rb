# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class EPSS < Platform::Objects::Base
      description CVEEPSS::DESCRIPTION

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        # Access to this object is managed by its parent SecurityAdvisory.
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # Access to this object is managed by its parent SecurityAdvisory.
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      field :percentage, Float, CVEEPSS::PERCENTAGE_DESCRIPTION, null: true
      field :percentile, Float, CVEEPSS::PERCENTILE_DESCRIPTION, null: true
    end
  end
end
