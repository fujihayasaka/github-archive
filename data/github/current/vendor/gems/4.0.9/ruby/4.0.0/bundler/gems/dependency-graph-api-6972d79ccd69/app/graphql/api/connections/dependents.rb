module API
  module Connections
    class Dependents < GraphQL::Types::Relay::BaseConnection
      edge_type(API::Types::Dependent.edge_type)

      field :estimated_repository_count, Integer, null: false

      def estimated_repository_count
        # We return a 0 here because a package manager in preview
        # won't have any dependents and the `nodes` object is an empty
        # array, instead of a connection object.
        return 0 unless object.nodes.respond_to?(:estimated_dependent_repository_count)
        object.nodes.estimated_dependent_repository_count
      end

      field :dependentEndCursor, String, null: true

      def dependentEndCursor
        last_dependent = object.nodes.try(:last_dependent)
        last_dependent ? object.cursor_from_node(last_dependent) : nil
      end
    end
  end
end
