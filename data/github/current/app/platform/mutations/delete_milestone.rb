# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteMilestone < Platform::Mutations::Base
      description "Delete an existing milestone."
      visibility :internal
      minimum_accepted_scopes ["public_repo"]

      argument :id, ID, "The Node ID of the milestone to be deleted.", required: true, loads: Objects::Milestone, as: :milestone
      field :milestone, Objects::Milestone, "The deleted milestone.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, milestone:, **inputs)
        permission.async_owner_if_org(milestone.repository).then do |org|
          permission.access_allowed? :delete_milestone, current_org: org, repo: milestone.repository, allow_integrations: true, allow_user_via_granular_actor: true
        end
      end

      def resolve(milestone:, **inputs)
        context[:permission].authorize_content(:issue, :update, repo: milestone.repository)
        if milestone.destroy
          { milestone: milestone }
        else
          raise Errors::Unprocessable.new("Could not delete milestone.")
        end
      end
    end
  end
end
