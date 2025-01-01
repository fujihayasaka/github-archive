# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2ItemFieldIterationValue < Platform::Objects::Base
      implements Platform::Interfaces::ProjectV2ItemFieldValueCommon

      description "The value of an iteration field in a Project item."

      class << self
        # Delegate static methods to the ProjectV2 helper.
        delegate :async_api_can_access?, to: Platform::Helpers::ProjectV2ItemFieldValue
        delegate :async_viewer_can_see?, to: Platform::Helpers::ProjectV2ItemFieldValue
      end

      Platform::Helpers::ProjectV2ItemFieldValue
        .generic_definition(
          Platform::Helpers::ProjectV2::Prefix.new("PVTFIV", :opvtifiv, :upvtifiv)
        )
        .call(self)

      field :iteration_id, String, null: false, description: "The ID of the iteration."

      field :title, String, null: false, description: "The title of the iteration."

      field :duration, Integer, null: false, description: "The duration of the iteration in days."

      field :start_date, Scalars::Date, null: false, description: "The start date of the iteration."

      field :title_html, String, null: false, description: "The title of the iteration, with HTML."

      def self.load_from_global_id(id)
        Models::ProjectItemFieldIterationValue.load_from_global_id(id)
      end
    end
  end
end
