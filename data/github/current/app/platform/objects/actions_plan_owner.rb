# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ActionsPlanOwner < Platform::Objects::Base
      description "Represents the entity (User, Organization or Business) used by the Actions Runtime for limiting build concurrency."

      scopeless_tokens_as_minimum

      visibility :internal

      def self.async_viewer_can_see?(permission, _object)
        # TODO this object will never be public
        permission.hidden_from_public?(self)
      end

      def self.async_api_can_access?(permission, _object)
        # TODO this object will never be public
        permission.hidden_from_public?(self)
      end

      field :id, ID, "The owner's global relay id", null: false

      field :name, String, "The name of the owner.", null: false

      field :plan_name, String, "The name of the plan.", null: false, method: :async_plan_name

      field :customer_id, Int, "Customer id for the plan owner", null: true

      field :type, String, "The classname of the owner.", null: false
    end
  end
end
