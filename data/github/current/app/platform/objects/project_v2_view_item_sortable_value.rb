# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2ViewItemSortableValue < Platform::Objects::Base
      description "Represents a sortable value for a ProjectV2ViewItem."
      required_capabilities [:mobile_only_schema_mask]

      # This object is a simple value object that cannot be loaded outside of the context of a ProjectV2ViewItem.
      # Permission checks are done at the ProjectV2ViewItem level.
      def self.async_api_can_access?(permission, object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # This object is a simple value object that cannot be loaded outside of the context of a ProjectV2ViewItem.
      # Permission checks are done at the ProjectV2ViewItem level.
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      field :type, Platform::Enums::ProjectV2ViewItemSortableValueType, "The type of the value", null: false
      field :value, String, "The value of the value, as a String", null: true
    end
  end
end
