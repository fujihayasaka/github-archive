# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class FeatureFlagState < Platform::Objects::Base
      description "feature flag with its enabled state"
      mobile_only true

      field :name, String, "Name of the feature flag", null: false

      def name
        object.name
      end

      field :enabled, Boolean, "enabled value", null: false

      def enabled
        object.enabled
      end

      def self.async_api_can_access?(_permission, _object)
        # No special API permissions, pre authorized by scoping to viewer in user.rb#feature_flags
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      def self.async_viewer_can_see?(permission, object)
        # No special API permissions, pre authorized by scoping to viewer in user.rb#feature_flags
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

    end
  end
end
