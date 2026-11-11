# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteTeam < Platform::Mutations::Base
      description "Deletes a team."
      visibility :internal

      minimum_accepted_scopes ["write:org"]

      argument :team_id, ID, "The Team ID to delete.", required: true, loads: Objects::Team
      field :is_destroyed, Boolean, "Whether or not the team was successfully destroyed.", null: true

      def resolve(team:, **inputs)

        viewer = context[:viewer]
        actor  = context[:actor]

        viewer_error = "#{viewer.display_login} does not have permission to delete this team."

        if actor.can_have_granular_permissions?
          if !team.organization.resources.members.writable_by?(actor)
            raise Errors::Forbidden.new(viewer_error)
          end
        else
          unless team.adminable_by?(viewer)
            raise Errors::Forbidden.new(viewer_error)
          end

          if team.has_child_teams? && !team.organization.adminable_by?(viewer)
            raise Errors::Forbidden.new("Only organization admins can delete parent teams.")
          end
        end

        if team.legacy_owners?
          DestroyTeamJob.perform_later(team.id)

          team.organization.update_attribute(:destroy_owners_team_attempted_at, Time.now)
        else
          team.destroy
        end

        if team.errors.any?
          raise Errors::Unprocessable.new(team.errors.full_messages.join(", "))
        end

        { is_destroyed: true }
      end
    end
  end
end
