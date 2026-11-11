module API
  module Types
    class Dependent < Types::BaseObject
      description "A dependent"

      implements GraphQL::Types::Relay::Node

      global_id_field :id

      field :repository_id, Integer, method: :github_repository_id, null: true
      field :package_name, String, null: true
      field :requirements, String, null: true
      field :manifest_type, String, null: true
      field :manifest_path, String, null: true
      field :manifest_filename, String, null: true
      field :scope, String, null: true
    end
  end
end
