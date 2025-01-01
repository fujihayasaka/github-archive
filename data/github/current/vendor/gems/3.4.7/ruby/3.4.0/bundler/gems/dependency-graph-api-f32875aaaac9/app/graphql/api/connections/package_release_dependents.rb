module API
  module Connections
    class PackageReleaseDependents < GraphQL::Types::Relay::BaseConnection
      edge_type(API::Types::PackageReleaseDependent.edge_type)

      field :total_count, Integer, null: false

      def total_count
        object.nodes.total_count
      end

      field :vulnerability_severities, [API::Types::PackageReleaseVulnerabilitySeverity], null: false

      def vulnerability_severities
        object.nodes.vulnerability_severities
      end

      field :licenses, [API::Types::PackageReleaseLicense], null: false

      def licenses
        object.nodes.licenses
      end
    end
  end
end
