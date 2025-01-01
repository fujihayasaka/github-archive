# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Minimizable
      include Platform::Interfaces::Base
      description "Entities that can be minimized."
      visibility :public

      field :viewer_can_minimize, Boolean, description: "Check if the current viewer can minimize this object.", null: false

      def viewer_can_minimize
        @object.async_minimizable_by?(@context[:viewer])
      end

      field :viewer_can_see_minimize_button, Boolean, description: "Check if the viewer should see the minimize button in the UI.", visibility: :internal, null: false

      def viewer_can_see_minimize_button
        @object.async_minimizable_by?(@context[:viewer]).then do |can_minimize|
          # Return false if object is not part of a repo
          next false unless @object.respond_to?(:repository)

          # Return result if actor isn't a site admin
          next can_minimize unless @context[:viewer].try(:site_admin?)

          # If the user is a site admin, only show them the minimize button if they can push to the repo
          @object.async_repository.then do |repo|
            repo.async_pushable_by?(@context[:viewer]).then do |can_push|
              can_push && can_minimize
            end
          end
        end
      end

      field :viewer_can_see_unminimize_button, Boolean, description: "Check if the viewer can see unminimize button in the UI.", visibility: :internal, null: false

      def viewer_can_see_unminimize_button
        @object.async_unminimizable_by?(@context[:viewer]).then do |can_unminimize|
          # Return false if object is not part of a repo
          next false unless @object.respond_to?(:repository)

          # Return result if actor isn't a site admin
          next can_unminimize unless @context[:viewer].try(:site_admin?)

          # If the user is a site admin, only show them the unminimize button if they can push to the repo
          @object.async_repository.then do |repo|
            repo.async_pushable_by?(@context[:viewer]).then do |can_push|
              can_push && can_unminimize
            end
          end
        end
      end


      field :is_minimized, Boolean, description: "Returns whether or not a comment has been minimized.", null: false, method: :minimized?

      # This does not use an enum, despite the fixed set of values, because (a) this was implemented as as a string
      # 4 years ago, and changing it would be a breaking change and (b) the values here are lower-case and kebab-case,
      # when by convention all enum values in our GraphAPI are upper-case and snake-case.
      field :minimized_reason, String, description: "Returns why the comment was minimized. One of `abuse`, `off-topic`, `outdated`, `resolved`, `duplicate` and `spam`. Note that the case and formatting of these values differs from the inputs to the `MinimizeComment` mutation.", null: true
    end

  end
end
