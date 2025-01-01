# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2ItemFieldUserValue < Platform::Objects::Base
      description "The value of a user field in a Project item."

      class << self
        # Delegate static methods to the ProjectV2 helper.
        delegate :async_api_can_access?, to: Platform::Helpers::ProjectV2ItemFieldValue
        delegate :async_viewer_can_see?, to: Platform::Helpers::ProjectV2ItemFieldValue
      end

      visibility :public, environments: [:dotcom, :enterprise]

      minimum_accepted_scopes ["read:project"]

      field :users, Connections.define(Objects::User), description: "The users for this field", null: true
      def users
        # Filter out bot users from the results only if feature flag is enabled
        if context[:viewer]&.feature_enabled?(:assignees_filter_bots)
          non_bot_users = @object.users.reject(&:bot?)
          ArrayWrapper.new(non_bot_users)
        else
          ArrayWrapper.new(@object.users)
        end
      end

      field :actors, Connections.define(Interfaces::Actor), description: "The actors for this field", null: true, required_capabilities: [:mobile_only_schema_mask]
      def actors
        ArrayWrapper.new(@object.users)
      end

      field :field, Platform::Unions::ProjectV2FieldConfiguration,  description: "The field that contains this value.", null: false
    end
  end
end
