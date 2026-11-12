module API
  module Types
    class VulnerableVersionRange < Types::BaseObject
      description "A vulnerablility version range"

      implements GraphQL::Types::Relay::Node

      global_id_field :id

      field :github_id, Integer, null: true
      field :package_name, String, null: true
      field :version_range, String, null: true
    end
  end
end
