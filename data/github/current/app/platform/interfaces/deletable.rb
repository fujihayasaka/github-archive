# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Deletable
      include Platform::Interfaces::Base
      description "Entities that can be deleted."

      field :viewer_can_delete, Boolean, description: "Check if the current viewer can delete this object.", null: false

      def viewer_can_delete
        @object.async_viewer_can_delete?(@context[:viewer])
      end

      field :viewer_can_see_delete_button, Boolean, description: "Check if the viewer should see the delete button in the UI.", visibility: :internal, null: false

      def viewer_can_see_delete_button
        @object.async_viewer_can_delete?(@context[:viewer]).then do |can_delete|
          if @object.respond_to?(:repository) && @context[:viewer].try(:site_admin?)
            # If the user is a site admin, only show them the delete button if they can push to the repo
            @object.async_repository.then do |repo|
              repo.async_pushable_by?(@context[:viewer]).then do |can_push|
                can_push && can_delete
              end
            end
          else
            can_delete
          end
        end
      end
    end
  end
end
