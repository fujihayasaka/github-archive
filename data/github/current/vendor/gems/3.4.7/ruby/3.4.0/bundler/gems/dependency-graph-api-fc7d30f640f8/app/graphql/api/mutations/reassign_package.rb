module API
  module Mutations
    class ReassignPackage < Types::BaseMutation
      argument :package_name, String, required: true
      argument :package_manager, Enums::PackageManager, required: true
      argument :repository_id, Integer, required: true
      argument :client_mutation_id, String, required: false

      field :client_mutation_id, String, null: true

      def resolve(package_name:, package_manager:, repository_id:, client_mutation_id: nil)
        arguments = {
          names: package_name,
          package_manager: package_manager,
        }

        packages = Queries::PackageQuery.new(arguments).results
        if packages.size == 0
          raise GraphQL::ExecutionError.new("No package found")
        elsif packages.size > 1
          raise GraphQL::ExecutionError.new("More than one package found")
        end

        package = packages[0]

        Package.find_by(id: package.id).update(
          repository_id: repository_id,
          repository_id_certainty: PackageToRepoMapping::Certainty::OVERRIDE
        )

        { client_mutation_id: client_mutation_id }
      end
    end
  end
end
