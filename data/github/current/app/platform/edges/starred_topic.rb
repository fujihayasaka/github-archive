# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class StarredTopic < Edges::Base
      visibility :under_development

      description "Represents a starred topic."

      # Since the node is not `object.node`, override this to pass the real node
      def self.authorized?(object, context)
        object.node.async_starrable.then do |starrable|
          node_type.authorized?(starrable, context)
        end
      end

      field :node, Objects::Topic, null: false

      def node
        @object.node.async_starrable
      end

      field :starred_at, Scalars::DateTime, description: "Identifies when the item was starred.", null: false

      def starred_at
        @object.node.created_at
      end
    end
  end
end
