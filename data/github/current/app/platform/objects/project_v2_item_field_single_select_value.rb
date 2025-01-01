# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2ItemFieldSingleSelectValue < Platform::Objects::Base
      implements Platform::Interfaces::ProjectV2ItemFieldValueCommon

      description "The value of a single select field in a Project item."

      class << self
        # Delegate static methods to the ProjectV2 helper.
        delegate :async_api_can_access?, to: Platform::Helpers::ProjectV2ItemFieldValue
        delegate :async_viewer_can_see?, to: Platform::Helpers::ProjectV2ItemFieldValue
      end

      Platform::Helpers::ProjectV2ItemFieldValue
        .generic_definition(
          Platform::Helpers::ProjectV2::Prefix.new("PVTFSV", :opvtifsv, :upvtifsv)
        )
        .call(self)

      field :option_id, String, description: "The id of the selected single select option.", null: true

      field :name, String, description: "The name of the selected single select option.", null: true

      field :name_html, String, description: "The html name of the selected single select option.", null: true

      field :description, String, description: "A plain-text description of the selected single-select option, such as what the option means.", null: true

      field :description_html, String, description: "The description of the selected single-select option, including HTML tags.", null: true

      field :color, Platform::Enums::ProjectV2SingleSelectFieldOptionColor, description: "The color applied to the selected single-select option.", null: false

      def self.load_from_global_id(id)
        Models::ProjectItemFieldSingleSelectValue.load_from_global_id(id)
      end
    end
  end
end
