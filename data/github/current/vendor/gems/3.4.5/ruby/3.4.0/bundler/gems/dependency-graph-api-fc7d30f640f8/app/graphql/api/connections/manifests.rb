module API
  module Connections
    class Manifests < GraphQL::Types::Relay::BaseConnection
      edge_type(API::Types::Manifest.edge_type)

      field :total_count, Integer, null: false

      def total_count
        options = object.arguments.to_h
        Queries::ManifestsQuery.new(**options).total_count_for_repository
      end
    end
  end
end
