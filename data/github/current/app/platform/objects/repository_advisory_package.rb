# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoryAdvisoryPackage < Platform::Objects::Base
      visibility :internal
      # We only use this internally on custom-og-image, but let's expose as
      # "Package" (and not "Affected Product") to remain consistent with
      # SecurityAdvisoryPackages (will make life easier in the case we ever make
      # this API public)
      model_name "RepositoryAdvisoryAffectedProduct"

      description "An individual package"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      field :ecosystem, String, "The ecosystem the package belongs to, e.g. RubyGems, npm", null: false
      field :name, String, "The package name", method: :package, null: false
    end
  end
end
