# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateParentInitiatedTeamChangeParentRequest < Platform::Mutations::Base
      description "Creates a pending parent initiated team change parent request"
      visibility :internal

      minimum_accepted_scopes ["write:org"]

      argument :parent_team_id, ID, "The parent team that initiated this request", required: true, loads: Objects::Team
      argument :child_team_id, ID, "The child team that will be moved as a result of this request", required: true, loads: Objects::Team

      field :request, Objects::TeamChangeParentRequest, "The pending request", null: true

      def resolve(child_team:, parent_team:, **inputs)
        async_ensure_viewer_can_request_parent_change!(context, parent_team)
        .then { ensure_target_team_can_become_child!(parent_team, child_team) }
        .then { create_team_change_parent_request_initiated_by_child!(parent_team, child_team, context[:viewer]) }.sync
      end

      def async_ensure_viewer_can_request_parent_change!(context, parent_team)
        parent_team.async_adminable_by?(context[:viewer]).then do |can_maintain|
          unless can_maintain
            raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to initiate a request to change parent teams.")
          end
        end
      end

      def ensure_target_team_can_become_child!(requesting_team, target_team)
        success, error = requesting_team.can_be_child_of?(target_team)

        unless success
          raise Errors::Validation.new(error)
        end
      end

      def create_team_change_parent_request_initiated_by_child!(parent_team, child_team, requester)
        request = ::TeamChangeParentRequest.create_initiated_by_parent!(
          parent_team: parent_team,
          child_team: child_team,
          requester: requester,
        )

        { request: request }
      rescue ActiveRecord::RecordInvalid => e
        raise Errors::Validation.new(e.message)
      end
    end
  end
end
