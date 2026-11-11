module API
  module Types
    class PackageReleaseDependent < Types::BaseObject
      description "TODO: A versioned software library release"

      implements GraphQL::Types::Relay::Node

      global_id_field :id

      field :package_release, Types::PackageRelease, null: true

      field :dependents_count, Integer, null: true
      field :dependents, API::Connections::RepositoryDependents, null: true, connection: true do
        argument :owner_ids, [Integer], required: true
        argument :dependent_name, String, required: false
      end

      def dependents(owner_ids:, dependent_name: nil)
        if owner_ids.empty?
          raise GraphQL::ExecutionError.new("Missing required ownerIds on dependents")
        end

        arguments = {
          owner_ids: owner_ids,
          dependent_name: dependent_name,
          package_name: object.package_release.package.name,
          version: object.package_release.name,
          package_manager: object.package_release.package.package_manager
        }

        Queries::RepositoryDependentsQuery.new(**arguments)
      end

      field :vulnerabilities_count, Integer, null: true
    end
  end
end
