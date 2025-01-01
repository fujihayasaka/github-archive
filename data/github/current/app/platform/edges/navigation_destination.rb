# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class NavigationDestination < Edges::Base
      visibility :internal

      # Override this since the node isn't `object.node`
      def self.authorized?(object, context)
        node_type.authorized?(object.node.destination, context)
      end

      description "Represents a viewer's pageview metadata about a suggestion"

      node_type Unions::NavigationDestination

      def node
        @object.node.destination
      end

      field :visit_count, Integer, "Number of times viewer has visited this node", null: true
      def visit_count
        @object.node.visit_count
      end
      field :last_visited_at, Scalars::DateTime, "When the viewer last visited this node", null: true
      def last_visited_at
        @object.node.last_visited_at
      end
    end
  end
end
