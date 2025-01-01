module API
  module Types
    class RepositoriesUsingDependency < Types::BaseObject
      graphql_name "RepositoriesUsingDependency"
      description "A particular dependency and all the repositories owned by a particular " \
        "user or organization that rely on that dependency."

      field :dependency_id, Integer, null: false
      field :repository_owner_id, Integer, null: false
      field :repositories, [Integer], null: false
    end
  end
end
