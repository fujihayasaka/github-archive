# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SecurityAdvisoryPackage < Platform::Objects::Base
      visibility :public

      description "An individual package"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # Enterprise customers reported getting an error and not being able to
        # query this field from an "api" origin. Upon investigation of the
        # combinations of Runtime and Origin, it was decided the permission
        # could be simplified to all cases, including enterprise - rest_api,
        # a case previously not permitted.

        # _object is a hash so no parent permission checking is possible.
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # Access to this object is managed by its parent SecurityAdvisory.
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum


      field :ecosystem, Enums::SecurityAdvisoryEcosystem, "The ecosystem the package belongs to, e.g. RUBYGEMS, NPM", null: false
      field :name, String, "The package name", null: false
    end
  end
end
