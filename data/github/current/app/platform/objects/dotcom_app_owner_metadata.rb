# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class DotcomAppOwnerMetadata < Platform::Objects::Base
      description "Represents metadata synchronized from Dotcom about the owner of a synchronized Application"
      visibility :internal, environments: [:dotcom]

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      # Ability check for an Integration object
      def self.async_viewer_can_see?(permission, object)
        return false unless GitHub.multi_tenant_enterprise?

        Platform::Loaders::ActiveRecordAssociation.load(object, :local_app) do |local_app|
          local_app.async_readable_by?(permission.viewer)
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, app_metadata)
        return false unless GitHub.multi_tenant_enterprise?

        Platform::Loaders::ActiveRecordAssociation.load(app_metadata, :local_app) do |local_app|
          local_app.async_readable_by?(permission.viewer)
        end
      end

      field :login, String, "The login of the owner in Dotcom.", null: false
      field :avatar_url, Scalars::URI, "The avatar URL of the owner in Dotcom.", null: true
    end
  end
end
