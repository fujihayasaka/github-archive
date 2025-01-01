# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteProjectCard < Platform::Mutations::Base
      description "Deletes a project card."

      minimum_accepted_scopes ["public_repo", "write:org"]

      argument :card_id, ID, "The id of the card to delete.", required: true, loads: Objects::ProjectCard

      field :deleted_card_id, ID, "The deleted card ID.", null: true

      field :column, Objects::ProjectColumn, "The column the deleted card was in.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, card:, **inputs)
        Platform::Helpers::ProjectDeprecation.ensure_api_availability(permission.viewer)

        card.async_project.then do |project|
          permission.typed_can_modify?("UpdateProject", project: project)
        end
      end

      def resolve(card:, **inputs)
        column = card.column
        deletedId = card.global_relay_id

        helper = Platform::Helpers::DeleteProjectCard.new(card, context)
        helper.delete_card

        {
          deleted_card_id: deletedId,
          column: column,
        }
      end
    end
  end
end
