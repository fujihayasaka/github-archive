module API
  module Types
    class AbstractDependent < Types::BaseObject
      description "An abstract dependent"

      implements GraphQL::Types::Relay::Node

      global_id_field :id

      field :repository_id, Integer, method: :github_repository_id, null: true
      field :owner_id, Integer, method: :github_owner_id, null: true

      field :name, String, null: true

      def name
        object.name if object.respond_to?(:name)
      end
    end
  end
end
