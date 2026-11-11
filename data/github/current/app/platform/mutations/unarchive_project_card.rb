# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UnarchiveProjectCard < Platform::Mutations::Base
      description "Unarchives a project card."
      visibility :internal

      minimum_accepted_scopes ["public_repo"]

      argument :project_card_id, ID, "The ProjectCard ID to unarchive.", required: true, loads: Objects::ProjectCard, as: :card

      field :project_card, Objects::ProjectCard, "The unarchived ProjectCard.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, card:, **inputs)
        Platform::Helpers::ProjectDeprecation.ensure_api_availability(permission.viewer)

        permission.typed_can_modify?("UpdateProjectCard", card: card)
      end

      def resolve(card:, **inputs)
        project = card.project

        context[:permission].authorize_content(:project, :update, project: project)

        unless project.writable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to update project cards on this repository.")
        end

        if card.unarchive
          { project_card: card }
        else
          raise Errors::Unprocessable.new(card.errors.full_messages.join(", "))
        end
      end
    end
  end
end
