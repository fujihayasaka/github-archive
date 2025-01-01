# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class EnterprisePendingMemberInvitation < Connections::Base
      graphql_name "EnterprisePendingMemberInvitationConnection"

      total_count_field

      field :total_unique_user_count, Int,
        description: "Identifies the total count of unique users in the connection.",
        null: false

      def total_unique_user_count
        @object.parent.unique_pending_member_invitation_count
      end
    end
  end
end
