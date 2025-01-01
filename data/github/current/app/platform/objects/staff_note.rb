# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class StaffNote < Platform::Objects::Base
      description "Staff note from stafftools. For internal use only."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name)
      end

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      field :id, ID, description: "The Node ID of the StaffNote object", method: :global_relay_id, null: false

      field :body, String, "Note body.", null: true

      field :creator, Unions::Account, "Note creator.", null: true, method: :async_user

      field :is_pinned, Boolean, "Whether or not the staff note is pinned.", null: false

      created_at_field
      updated_at_field
    end
  end
end
