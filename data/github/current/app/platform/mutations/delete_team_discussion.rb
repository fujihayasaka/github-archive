# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteTeamDiscussion < Platform::Mutations::Base
      description "Deletes a team discussion."

      minimum_accepted_scopes ["write:discussion"]

      argument :id, ID, "The discussion ID to delete.", required: true, loads: Objects::TeamDiscussion, as: :discussion

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, discussion:, **inputs)
        discussion.async_organization.then do |org|
          permission.access_allowed?(
            :delete_team_discussion,
            resource: discussion,
            organization: org,
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true)
        end
      end

      def resolve(discussion:, **inputs)

        unless discussion.async_viewer_can_delete?(context[:viewer]).sync
          message = (
            "#{context[:viewer].display_login} does not have permission to delete the discussion " +
            "'#{discussion.global_relay_id}'.")
          raise Errors::Forbidden.new(message)
        end

        unless discussion.destroy
          raise Errors::Validation.new(discussion.errors.full_messages.to_sentence)
        end

        {}
      end
    end
  end
end
