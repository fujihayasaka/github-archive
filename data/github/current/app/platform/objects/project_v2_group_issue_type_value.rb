# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2GroupIssueTypeValue < Platform::Objects::Base
      description "Value when a view is grouped by an issue type column"
      minimum_accepted_scopes ["read:org"]
      required_capabilities [:mobile_only_schema_mask]

      def self.async_api_can_access?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      field :name, String, "The name of the issue type shared by all the items for the grouped field", null: true, method: :value
    end
  end
end
