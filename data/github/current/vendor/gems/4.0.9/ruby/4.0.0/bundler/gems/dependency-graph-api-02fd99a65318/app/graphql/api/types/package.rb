module API
  module Types
    class Package < Types::BaseObject
      graphql_name "Package"
      description "A software library"

      implements GraphQL::Types::Relay::Node

      global_id_field :id

      field :name, String, null: true

      field :package_manager, Enums::PackageManager, null: true

      field :package_manager_human_name, String, null: true

      def package_manager_human_name
        object.package_manager&.human_name
      end

      field :repository_id, Integer, null: true

      field :repository_nwo, String, null: true

      field :debug_association_explanation, String, null: true

      field :debug_should_be_associated_to_repo, Boolean, null: true

      field(:abstract_repository_dependents, Connections::AbstractRepositoryDependents,
        max_page_size: 100,
        null: true,
        connection: true,
        extensions: [GraphQLFieldTimerExtension],
      ) do
        argument :owner_id, Integer, "User or organization ID", required: false
      end

      def abstract_repository_dependents(owner_id: nil)
        Queries::AbstractRepositoryDependentsQuery.new(
          depends_on: object,
          github_owner_id: owner_id,
        )
      end

      field(:abstract_package_dependents, Connections::AbstractPackageDependents,
        max_page_size: 100,
        null: true,
        connection: true,
        extensions: [GraphQLFieldTimerExtension],
      ) do
        argument :owner_id, Integer, "User or organization ID", required: false
      end

      def abstract_package_dependents(owner_id: nil)
        Queries::AbstractPackageDependentsQuery.new(
          depends_on: object,
          github_owner_id: owner_id,
        )
      end
    end
  end
end
