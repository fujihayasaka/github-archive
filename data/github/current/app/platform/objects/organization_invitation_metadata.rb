# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class OrganizationInvitationMetadata < Platform::Objects::Base
      description "Information about organization invitations."

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

      field :accepted_invitations_count, Integer, description: "Count of accepted invitations.", null: false
      field :cancelled_invitations_count, Integer, description: "Count of cancelled invitations.", null: false
      field :email_invitee_invitations_count, Integer, description: "Count of invitations sent to email addresses.", null: false
      field :total_invitations_count, Integer, description: "Count of total invitations.", null: false
      field :user_invitee_invitations_count, Integer, description: "Count of invitations sent to GitHub users.", null: false
    end
  end
end
