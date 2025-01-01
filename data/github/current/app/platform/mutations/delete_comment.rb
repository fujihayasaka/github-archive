# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteComment < Platform::Mutations::Base
      description "Delete a comment."

      # Let's keep this internal for now since the Deletable interface includes
      # many things other than comments. More context see: https://github.com/github/github/pull/97582
      visibility :internal
      minimum_accepted_scopes %w[public_repo gist]

      argument :id, ID, "The id of the comment to delete.", required: true, loads: Interfaces::Deletable, as: :comment

      field :comment, Interfaces::Comment, "The comment that was just deleted.", null: true

      def resolve(comment:, **inputs)

        if !context[:actor].can_have_granular_permissions? && !comment.async_viewer_can_delete?(context[:viewer]).sync
          raise Errors::Forbidden.new("Viewer not authorized")
        end

        if comment && comment.destroy
          { comment: comment }
        else
          raise Errors::Unprocessable.new("Could not delete comment.")
        end
      end
    end
  end
end
