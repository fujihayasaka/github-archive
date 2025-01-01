# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ApprovePendingTeamChangeParentRequest < Platform::Mutations::Base
      description "Approves a pending team change parent request and moves the child team to the parent team"
      visibility :internal

      minimum_accepted_scopes ["write:org"]

      argument :request_id, ID, "The pending team change parent request ID to approve", required: true, loads: Objects::TeamChangeParentRequest

      field :request, Objects::TeamChangeParentRequest, "The request that was approved", null: true

      def resolve(request:, **inputs)

        async_ensure_viewer_can_approve_request!(context, request)
        .then do
          begin
            request.approve(actor: context[:viewer])

            TeamChangeParentRequest.cleanup_duplicates_to(request, context[:viewer])

            next { request: request }
          rescue ::TeamChangeParentRequest::AlreadyApprovedError
            raise Errors::Validation.new("The request has already been approved")
          end
        end.sync
      end

      def async_ensure_viewer_can_approve_request!(context, request)
        request.async_requested_team.then do |requested_team|
          requested_team.async_adminable_by?(context[:viewer]).then do |can_maintain|
            unless can_maintain
              raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to approve this request.")
            end
          end
        end
      end
    end
  end
end
