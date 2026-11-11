# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class EnterpriseMemberInvitations < Resolvers::Base
      argument :query, String, "The search string to look for.", required: false
      argument :order_by, Inputs::EnterpriseMemberInvitationOrder,
        "Ordering options for pending enterprise member invitations returned from the connection.",
        required: false, default_value: { field: "created_at", direction: "DESC" }

      type Connections.define(Objects::EnterpriseMemberInvitation), null: false

      def resolve(query: nil, order_by: nil)
        ensure_business_can_use_api!(object)

        object.async_customer.then do
          if !object.can_invite_unaffiliated_user_accounts?
            raise Errors::Unprocessable.new("Enterprise member invitations are disabled in this environment")
          end

          object.pending_admin_invitations(query: query,
                                           order_by_field: order_by&.dig(:field),
                                           order_by_direction: order_by&.dig(:direction),
                                           role: :unaffiliated)
        end.sync
      end
    end
  end
end
