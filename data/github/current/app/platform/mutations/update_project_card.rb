# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateProjectCard < Platform::Mutations::Base
      description "Updates an existing project card."

      # For a note card, a user will need the least permissive scope.
      # For an issue/PR card, a user must provide a scope with access to the resource.
      minimum_accepted_scopes ["public_repo", "write:org"]

      argument :project_card_id, ID, "The ProjectCard ID to update.", required: true, loads: Objects::ProjectCard, as: :card
      argument :is_archived, Boolean, "Whether or not the ProjectCard should be archived", required: false
      argument :note, String, "The note of ProjectCard.", required: false

      field :project_card, Objects::ProjectCard, "The updated ProjectCard.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, card:, **inputs)
        card.async_project.then do |project|
          permission.typed_can_modify?("UpdateProject", project: project)
        end
      end

      def resolve(card:, **inputs)
        if !card.is_note? && !card.content.readable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to update this project card.")
        end

        project = card.project

        context[:permission].authorize_content(:project, :update, project: project)

        unless project.writable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to update project cards on this repository.")
        end

        card.note = inputs[:note] if inputs.key?(:note)

        if card.save
          if inputs.key?(:is_archived)
            if inputs[:is_archived]
              card.archive
            else
              card.unarchive
            end
          end

          { project_card: card }
        else
          raise Errors::Unprocessable.new(card.errors.full_messages.join(", "))
        end
      end
    end
  end
end
