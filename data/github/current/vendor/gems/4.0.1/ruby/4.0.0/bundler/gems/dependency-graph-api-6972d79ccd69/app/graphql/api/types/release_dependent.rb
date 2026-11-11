module API
  module Types
    class ReleaseDependent < Types::BaseObject
      description "A dependent of a package release"

      implements GraphQL::Types::Relay::Node

      global_id_field :id

      field :repository_id, Integer, method: :github_repository_id, null: true
      field :package_name, String, null: true
      field :requirements, String, null: true
      field :manifest_type, String, null: true
      field :manifest_path, String, null: true
      field :manifest_filename, String, null: true

      # The "package name" in this context is the name of the dependent, but the object referred to here
      # is built from a query to ManifestEntry, where "package name" is the name of the declared dependency.
      # `dependent_package_name` comes from the query in Queries::RepositoryDependentsQuery.
      def package_name
        object.dependent_package_name
      end
    end
  end
end
