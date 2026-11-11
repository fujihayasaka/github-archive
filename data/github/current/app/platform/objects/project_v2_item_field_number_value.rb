# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2ItemFieldNumberValue < Platform::Objects::Base
      implements Platform::Interfaces::ProjectV2ItemFieldValueCommon

      description "The value of a number field in a Project item."

      class << self
        # Delegate static methods to the ProjectV2 helper.
        delegate :async_api_can_access?, to: Platform::Helpers::ProjectV2ItemFieldValue
        delegate :async_viewer_can_see?, to: Platform::Helpers::ProjectV2ItemFieldValue
      end

      Platform::Helpers::ProjectV2ItemFieldValue
        .generic_definition(
          Platform::Helpers::ProjectV2::Prefix.new("PVTFNV", :opvtifnv, :upvtifnv)
        )
        .call(self)

      field :number, Float, description: "Number as a float(#{MemexProjectColumnValue::NUMBER_VALUE_PRECISION})", null: true, method: :value

      def self.load_from_global_id(id)
        Models::ProjectItemFieldNumberValue.load_from_global_id(id)
      end
    end
  end
end
