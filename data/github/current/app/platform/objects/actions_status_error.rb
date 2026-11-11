# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ActionsStatusError < Platform::Objects::Base
      description "The status of actions for a repository"

      visibility :internal

      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      minimum_accepted_scopes ["site_admin"]

      def self.async_viewer_can_see?(permission, _object)
        # TODO this object will never be public
        permission.hidden_from_public?(self)
      end

      def self.async_api_can_access?(permission, _object)
        # TODO this object will never be public
        permission.hidden_from_public?(self)
      end

      field :reason, String, description: "The error representing why GitHub Actions is disabled", null: true

      def reason
        Billing::ActionsPermission.new(@object).status[:error][:reason]
      end

      field :message, String, description: "The message explaining why GitHub Actions is disabled", null: true

      def message
        Billing::ActionsPermission.new(@object).status[:error][:message]
      end
    end
  end
end
