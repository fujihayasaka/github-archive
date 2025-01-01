# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteUserContentEdit < Platform::Mutations::Base
      description "Delete a user content edit."

      visibility :under_development
      minimum_accepted_scopes ["public_repo"]

      argument :id, ID, "The id of the user content edit to delete.", required: true, loads: Objects::UserContentEdit, as: :user_content_edit
      field :user_content_edit, Objects::UserContentEdit, "The now deleted user content edit.", null: true

      def resolve(user_content_edit:, **inputs)
        if !context[:actor].can_have_granular_permissions? && !user_content_edit.async_viewer_can_delete?(context[:viewer]).sync
          raise Errors::Forbidden.new("Viewer not authorized")
        end

        if user_content_edit.deleted_at.present?
          return { user_content_edit: user_content_edit }
        end

        if user_content_edit.newest?
          raise Errors::Unprocessable.new("Unable to delete newest edit history")
        end

        user_content_edit.soft_delete!(context[:viewer])

        if user_content_edit.deleted_at.present?
          { user_content_edit: user_content_edit }
        else
          raise Errors::Unprocessable.new("Unable to delete edit history")
        end
      end
    end
  end
end
