# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class EnterpriseAdministratorInvitations < Resolvers::Base
      argument :query, String, "The search string to look for.", required: false
      argument :order_by, Inputs::EnterpriseAdministratorInvitationOrder,
        "Ordering options for pending enterprise administrator invitations returned from the connection.",
        required: false, default_value: { field: "created_at", direction: "DESC" }
      argument :role, Enums::EnterpriseAdministratorRole, "The role to filter by.", required: false

      type Connections.define(Objects::EnterpriseAdministratorInvitation), null: false

      def resolve(query: nil, order_by: nil, role: [:owner, :billing_manager])
        ensure_business_can_use_api!(object)

        object.pending_admin_invitations(query: query,
                                         order_by_field: order_by&.dig(:field),
                                         order_by_direction: order_by&.dig(:direction),
                                         role: role)
      end
    end
  end
end
