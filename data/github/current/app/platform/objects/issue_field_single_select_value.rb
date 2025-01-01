# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class IssueFieldSingleSelectValue < Platform::Objects::Base
      implements Platform::Interfaces::IssueFieldValueCommon

      feature_flag :issue_fields
      description "The value of a single select field in an Issue item."

      class << self
        # Delegate static methods to the ProjectV2 helper.
        delegate :async_api_can_access?, to: Platform::Helpers::IssueFieldValue
        delegate :async_viewer_can_see?, to: Platform::Helpers::IssueFieldValue
      end

      field :name, String, "The option's name.", null: false
      def name
        @object.option.name
      end

      field :description, String, "The option's plain-text description.", null: true
      def description
        @object.option.description
      end

      field :color, Enums::IssueFieldSingleSelectOptionColor, "The option's display color.", null: false
      def color
        @object.option.color
      end

      implements_node templates: [[:ifssv, :id]], as: "IFSSV", ready_date: "1970-01-01" do |issue_field_single_select_value|
        {
          prefix: :ifssv,
          id: issue_field_single_select_value.id
        }
      end

      def self.load_from_global_id(id)
        Platform::Loaders::ActiveRecord.load(::IssueFieldSingleSelectValue, id.to_i, security_violation_behaviour: :nil).then do |field_value|
          next unless field_value
          field_value.async_issue.then do
            field_value.async_issue_field.then do |issue_field|
              next unless issue_field

              # necessary to ensure options are properly preloaded for single select values
              issue_field.async_options.then do
                field_value
              end
            end
          end
        end
      end
    end
  end
end
