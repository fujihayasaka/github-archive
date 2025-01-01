# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Artifact < Platform::Objects::Base
      description "An artifact from a check suite."
      required_capabilities [:mobile_only_schema_mask]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        permission.async_repo_and_org_owner(object).then do |repo, org|
          permission.access_allowed?(
            :read_actions,
            resource: repo,
            current_repo: repo,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_check_suite.then do |check_suite|
          permission.typed_can_see?("CheckSuite", check_suite)
        end
      end

      scopeless_tokens_as_minimum

      database_id_field

      field :name, String, "The artifact's name.", null: false
      field :source_url, Scalars::URI, "The full URL to download all files in the artifact.", null: false, visibility: :internal
      field :size, Int, "The size of the artifact in bytes.", null: false
      field :expired, Boolean, "Whether or not the artifact has expired.", method: :expired?, null: false
      field :digest, String, "The artifact's SHA256 digest. This field will only be populated on artifacts uploaded with upload-artifact v4 or newer. For older versions, this field will be null.", null: true, visibility: { public: { environments: [:dotcom] } }
    end
  end
end
