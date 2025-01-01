module API
  module Connections
    class Dependencies < GraphQL::Types::Relay::BaseConnection
      edge_type(API::Types::Dependency.edge_type)

      field :total_count, Integer, null: false

      def total_count
        Queries::DependenciesQuery.new(
          dependent: object.parent
        ).dependencies_count
      end
    end
  end
end
