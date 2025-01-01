module API
  module Types
    class RepositoryDependencies < Types::BaseObject
      graphql_name "RepositoryDependencies"
      description "The dependencies of a Repository"

      field :direct_dependencies, [Integer], null: false
    end
  end
end
