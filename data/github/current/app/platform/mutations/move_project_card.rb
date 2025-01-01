# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class MoveProjectCard < Platform::Mutations::Base
      description "Moves a project card to another place."

      minimum_accepted_scopes ["public_repo", "write:org"]

      argument :card_id, ID, "The id of the card to move.", required: true, loads: Objects::ProjectCard
      argument :column_id, ID, "The id of the column to move it into.", required: true, loads: Objects::ProjectColumn
      argument :after_card_id, ID, "Place the new card after the card with this id. Pass null to place it at the top.", required: false, loads: Objects::ProjectCard

      field :card_edge, Objects::ProjectCard.edge_type, "The new edge of the moved card.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, card:, **inputs)
        card.async_project.then do |project|
          permission.typed_can_modify?("UpdateProject", project: project)
        end
      end

      def resolve(column:, card:, **inputs)
        project = card.project

        context[:permission].authorize_content(:project, :update, project: project)

        unless project.writable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to move project cards on this project.")
        end

        if ProjectCardRedactor.check_one(context[:viewer], card).redacted?
          raise Errors::Forbidden.new("#{context[:viewer].display_login} cannot move the project card because they do not have access to the associated content.")
        end

        if card.archived?
          raise Errors::Validation.new("The card must not be archived")
        end

        if card.project_id != column.project_id
          raise Errors::Validation.new("The card and column must be in the same project")
        end

        after_card = if inputs[:after_card]
          if inputs[:after_card].project_id != card.project_id
            raise Errors::Validation.new("The afterCard must be in the same project as the card")
          end

          if inputs[:after_card].column_id != column.id
            raise Errors::Validation.new("The afterCard must be in the column specified")
          end

          if inputs[:after_card].priority.nil?
            raise Errors::Validation.new("The afterCard must be prioritized")
          end

          inputs[:after_card]
        else
          nil
        end

        position = :top unless after_card

        begin
          column.prioritize_card!(card, after: after_card, position: position)
        rescue GitHub::Prioritizable::Context::LockedForRebalance
          raise Errors::ServiceUnavailable.new("This column is temporarily locked for maintenance. Please try again.")
        end

        column.project.notify_subscribers(
          action: "card_update",
          message: "#{context[:viewer].display_login} updated a card.",
          is_project_activity: card.show_activity?,
        )

        cards_items = ArrayWrapper.new(column.ordered_cards_for(context[:viewer]))
        cards_connection = Platform::ConnectionWrappers::ArrayWrapper.new(cards_items, context: context)
        {
          card_edge: GraphQL::Pagination::Connection::Edge.new(card, cards_connection),
        }
      end
    end
  end
end
