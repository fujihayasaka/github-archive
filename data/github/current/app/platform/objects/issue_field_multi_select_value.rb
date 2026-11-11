# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class IssueFieldMultiSelectValue < Platform::Objects::Base
      docs_category :issues
      implements Platform::Interfaces::IssueFieldValueCommon

      description "The value of a multi select field in an Issue item."

      class << self
        # Delegate static methods to the IssueFieldValue helper.
        delegate :async_api_can_access?, to: Platform::Helpers::IssueFieldValue
        delegate :async_viewer_can_see?, to: Platform::Helpers::IssueFieldValue
        delegate :async_viewer_can_modify?, to: Platform::Helpers::IssueFieldValue
      end

      field :value, String, "Comma-separated names of the selected options.", null: true
      def value
        @object.value
      end

      field :options, [Objects::IssueFieldSingleSelectOption, null: false],
        description: "The selected options.",
        null: false
      def options
        sorted = IssueFieldOption.sorted_options(@object.options)
        ArrayWrapper.new(sorted.map do |opt|
          Platform::Models::IssueFieldOptionWithFieldValueContext.new(opt, field_value: @object)
        end)
      end

      implements_node templates: [[:ifmsv, :id]], as: "IFMSV", ready_date: "1970-01-01" do |issue_field_multi_select_value|
        {
          prefix: :ifmsv,
          id: issue_field_multi_select_value.id
        }
      end

      def self.load_from_global_id(id)
        Platform::Loaders::ActiveRecord.load(::IssueFieldMultiSelectValue, id.to_i, security_violation_behaviour: :nil).then do |field_value|
          next unless field_value
          field_value.async_issue.then do
            field_value.async_issue_field.then do |issue_field|
              next unless issue_field

              # necessary to ensure options are properly preloaded for multi select values
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
