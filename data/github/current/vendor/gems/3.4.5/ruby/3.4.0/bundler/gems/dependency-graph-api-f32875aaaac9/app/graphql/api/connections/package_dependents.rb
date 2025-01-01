module API
  module Connections
    class PackageDependents < GraphQL::Types::Relay::BaseConnection
      edge_type(API::Types::Package.edge_type)

      field :total_count, Integer, null: false

      def total_count
        Queries::DependentsQuery.new(depends_on: object.parent).package_count
      end
    end
  end
end
