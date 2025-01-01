# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class PackageVersionsByMetadatum < Resolvers::PackageVersions
      argument :metadatum, Inputs::RegistryPackageMetadatum, "Filter on a specific metadatum.", required: true

      def filter(versions, arguments)
        return versions unless arguments[:metadatum]
        versions
          .joins(:metadata)
          .where(registry_package_metadata: { name: arguments[:metadatum][:name], value: arguments[:metadatum][:value] })
      end
    end
  end
end
