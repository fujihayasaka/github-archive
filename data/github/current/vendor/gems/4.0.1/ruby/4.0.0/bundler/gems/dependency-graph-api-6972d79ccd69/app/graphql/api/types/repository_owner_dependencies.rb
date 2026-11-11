module API
  module Types
    class RepositoryOwnerDependencies < Types::BaseObject
      graphql_name "RepositoryOwnerDependencies"
      description "The dependencies of all the repositories owned by a particular user or organization."

      field :dependencies, [Integer], null: false
      def dependencies
        if object.cache_key.present?
          Rails.cache.fetch("repository_owner_dependencies/#{object.cache_key}", expires_in: 12.hours) do
            object.dependencies
          end
        end
      end
    end
  end
end
