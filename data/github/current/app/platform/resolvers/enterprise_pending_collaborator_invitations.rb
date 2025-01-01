# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class EnterprisePendingCollaboratorInvitations < Resolvers::Base
      argument :query, String, "The search string to look for.", required: false
      argument :order_by, Inputs::RepositoryInvitationOrder,
        "Ordering options for pending repository collaborator invitations returned from the connection.",
        required: false, default_value: { field: "CREATED_AT", direction: "DESC" }

      type Connections.define(Objects::RepositoryInvitation), null: false

      def resolve(query: nil, order_by: nil)
        ensure_business_can_use_api!(object)

        invitations = if context[:permission].can_list_business_outside_collaborators?(object)
          object.pending_collaborator_invitations \
            query: query,
            order_by_field: order_by&.dig(:field),
            order_by_direction: order_by&.dig(:direction)
        else
          RepositoryInvitation.none
        end

        ArrayWrapper.new(invitations)
      end
    end
  end
end
