# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Reactable
      include Platform::Interfaces::Base
      description "Represents a subject that can be reacted on."

      global_id_field :id, description: "The Node ID of the Reactable object"

      database_id_field

      field :reaction_admin, Actor, visibility: :internal, method: :async_reaction_admin, description: "Admin user that can allow or disallow reactions to this type.", null: false
      field :reaction_path, String, visibility: :internal, method: :async_reaction_path, description: "Path for building URLs to scope and route reactions appropriately.", null: false
      field :viewer_can_react, Boolean, description: "Can user react to this subject", null: false

      def viewer_can_react
        @object.async_viewer_can_react?(@context[:viewer]).then do |viewer_can_react|
          next viewer_can_react unless viewer_can_react && @object.is_a?(PullRequestReviewComment)

          @object.async_reactable?
        end
      end

      field :reaction_groups, [Objects::ReactionGroup], description: "A list of reactions grouped by content left on the subject.", null: true

      def reaction_groups
        if @object.is_a?(PullRequest)
          @object.async_issue.then do |issue|
            Loaders::ReactionGroups.load(issue)
          end
        else
          Loaders::ReactionGroups.load(@object)
        end
      end

      field :reactions, Connections::Reaction, description: "A list of Reactions left on the Issue.", null: false, connection: true, numeric_pagination_enabled: true do
        argument :content, Enums::ReactionContent, "Allows filtering Reactions by emoji.", required: false
        argument :order_by, Inputs::ReactionOrder, "Allows specifying the order in which reactions are returned.", required: false
      end

      def reactions(**arguments)
        if @object.is_a?(PullRequest)
          @object.async_issue.then do |issue|
            ::Platform::Helpers::ReactionsQuery.list_reactions(issue, arguments)
          end
        else
          ::Platform::Helpers::ReactionsQuery.list_reactions(@object, arguments)
        end
      end
    end
  end
end
