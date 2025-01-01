# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class EnterpriseFailedInvitations < Resolvers::Base
      argument :query, String, "The search string to look for.", required: false
      argument :order_by, Inputs::OrganizationInvitationOrder,
        "Ordering options for failed enterprise organization member invitations returned from the connection.",
        required: false, default_value: { field: "created_at", direction: "DESC" }

      type Platform::Connections::EnterpriseFailedInvitation, null: false

      def resolve(query: nil, order_by: nil)
        ensure_business_can_use_api!(object)

        failed_invitations = if context[:permission].can_list_private_business_members?(object)
          object.failed_invitations(
            query: query,
            order_by_field: order_by&.dig(:field),
            order_by_direction: order_by&.dig(:direction),
          )
        else
          OrganizationInvitation.none
        end

        Promise.resolve(ArrayWrapper.new(failed_invitations))
      end
    end
  end
end
