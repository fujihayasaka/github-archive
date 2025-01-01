# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class EnterprisePendingMemberInvitations < Resolvers::Base
      argument :query, String, "The search string to look for.", required: false
      argument :order_by, Inputs::OrganizationInvitationOrder,
        "Ordering options for pending enterprise organization member invitations returned from the connection.",
        required: false, default_value: { field: "created_at", direction: "DESC" }
      argument :organization_logins, [String], "Only return invitations within the organizations with these logins", required: false
      argument :invitation_source, Enums::OrganizationInvitationSource, "Only return invitations matching this invitation source", required: false

      type Platform::Connections::EnterprisePendingMemberInvitation, null: false

      def resolve(query: nil, order_by: nil, organization_logins: nil, invitation_source: nil)
        ensure_business_can_use_api!(object)

        pending_invitations = if context[:permission].can_list_private_business_members?(object)
          object.pending_member_invitations(
            query: query,
            organizations: organization_logins,
            invitation_source: invitation_source,
            order_by_field: order_by&.dig(:field),
            order_by_direction: order_by&.dig(:direction),
          ).map do |org_invite|
            if org_invite.invitation_source == "unknown" && org_invite.external_identity.present?
              org_invite.invitation_source = "scim"
            end

            org_invite
          end
        else
          OrganizationInvitation.none
        end

        Promise.resolve(ArrayWrapper.new(pending_invitations))
      end
    end
  end
end
