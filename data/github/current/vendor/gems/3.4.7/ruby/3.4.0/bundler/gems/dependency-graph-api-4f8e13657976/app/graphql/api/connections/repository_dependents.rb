module API
  module Connections
    class RepositoryDependents < GraphQL::Types::Relay::BaseConnection
      edge_type(API::Types::ReleaseDependent.edge_type)

      field :exact_count, Integer, null: false
      def exact_count
        object.parent.dependents_count
      end

      field :lower_version_count, Integer, null: false
      def lower_version_count
        object.nodes.lower_version_count
      end

      field :upper_version_count, Integer, null: false
      def upper_version_count
        object.nodes.upper_version_count
      end
    end
  end
end
