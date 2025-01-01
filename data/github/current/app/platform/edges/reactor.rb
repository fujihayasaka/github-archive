# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class Reactor < Edges::Base
      description "Represents an author of a reaction."

      def self.authorized?(edge, context)
        Platform::Loaders::ActiveRecord.load(::User, edge.node).then do |user|
          self.node_type.authorized?(user, context)
        end
      end

      field :node, Unions::Reactor, description: "The author of the reaction.", null: false

      def node
        Platform::Loaders::ActiveRecord.load(::User, object.node).then do |user|
          user ||= ::User.ghost
        end
      end

      field :reacted_at, Scalars::DateTime, description: "The moment when the user made the reaction.", null: false

      def reacted_at
        reaction_group = @object.parent
        user_id = @object.node
        reaction_group.subject.reactions.find_by(user_id: user_id, content: reaction_group.emotion.content).created_at
      end
    end
  end
end
