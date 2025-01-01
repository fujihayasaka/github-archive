# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CancelPendingTeamChangeParentRequest < Platform::Mutations::Base
      description "Cancels a pending team change parent request"
      visibility :internal

      minimum_accepted_scopes ["write:org"]

      argument :request_id, ID, "The team change parent request ID to cancel", required: true, loads: Objects::TeamChangeParentRequest

      field :cancelled, Boolean, "Was the request cancelled?", null: true

      def resolve(request:, **inputs)

        begin
          request.cancel(actor: context[:viewer])
          { cancelled: true }
        rescue ::TeamChangeParentRequest::AlreadyApprovedError
          raise Errors::Validation.new("The request has already been approved")
        end
      end
    end
  end
end
