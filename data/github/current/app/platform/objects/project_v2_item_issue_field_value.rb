# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2ItemIssueFieldValue < Platform::Objects::Base
      description "The value of an issue field in a Project item."

      class << self
        # Delegate static methods to the ProjectV2 helper.
        delegate :async_api_can_access?, to: Platform::Helpers::ProjectV2ItemFieldValue
        delegate :async_viewer_can_see?, to: Platform::Helpers::ProjectV2ItemFieldValue
      end

      field :field, Platform::Unions::ProjectV2FieldConfiguration, description: "Field that contains this value.", null: false
      field :issue_field_value, Platform::Unions::ProjectV2IssueFieldValues,
        description: "Value of the Issue Field",
        null: true
      def issue_field_value
        Platform::Loaders::IssueFieldValues.load(@object.issue_field_value.issue_id, viewer: @context[:viewer]).then do |issue_field_values|
          issue_field_values.find { |value| value.issue_field.id == @object.issue_field_value.issue_field_id }
        end
      end
    end
  end
end
