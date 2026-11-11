# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddProjectCard < Platform::Mutations::Base
      description "Adds a card to a ProjectColumn. Either `contentId` or `note` must be provided but **not** both."

      minimum_accepted_scopes ["public_repo", "write:org"]

      argument :project_column_id, ID, "The Node ID of the ProjectColumn.", required: true, loads: Objects::ProjectColumn, as: :column
      argument :content_id, ID, "The content of the card. Must be a member of the ProjectCardItem union", required: false, loads: Unions::ProjectCardItem
      argument :note, String, "The note on the card.", required: false

      field :card_edge, Objects::ProjectCard.edge_type, "The edge from the ProjectColumn's card connection.", null: true

      field :project_column, Objects::ProjectColumn, "The ProjectColumn", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, column:, **inputs)
        Platform::Helpers::ProjectDeprecation.ensure_api_availability(permission.viewer)

        project = column.project
        permission.typed_can_modify?("UpdateProject", project: project)
      end

      def resolve(column:, **inputs)
        project = column.project
        helper = Platform::Helpers::AddProjectCard.new(project, context)
        helper.check_permissions

        if inputs[:note] != nil && inputs[:content] != nil
          raise Errors::Validation.new("You can't provide a note and contentId for a single card.")
        end

        if inputs[:note].nil? && inputs[:content].nil?
          raise Errors::Validation.new("You must provide either a note or a contentId.")
        end

        params = if inputs[:note]
          {
            content_type: "Note",
            note: inputs[:note],
          }
        else
          {
            content_type: "Issue",
            content_id: helper.content_from_inputs(inputs).id,
          }
        end

        begin
          card = ProjectCard.create_in_column(column, creator: context[:viewer], content_params: params)
        rescue GitHub::Prioritizable::Context::LockedForRebalance
          raise Errors::ServiceUnavailable.new("This column is temporarily locked for maintenance. Please try again.")
        end

        if card.persisted?
          project.notify_subscribers(
            action: "card_update",
            message: "#{context[:viewer].display_login} updated a card.",
          )

          {
            project_column: column,
            card_edge: helper.card_edge(card, column.ordered_cards_for(context[:viewer])),
          }
        else
          raise Errors::Unprocessable.new(card.errors.full_messages.join(", "))
        end
      end
    end
  end
end
