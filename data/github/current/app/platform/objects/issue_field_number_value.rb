# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class IssueFieldNumberValue < Platform::Objects::Base
      implements Platform::Interfaces::IssueFieldValueCommon

      feature_flag :issue_fields
      description "The value of a number field in an Issue item."

      class << self
        # Delegate static methods to the IssueFieldValue helper.
        delegate :async_api_can_access?, to: Platform::Helpers::IssueFieldValue
        delegate :async_viewer_can_see?, to: Platform::Helpers::IssueFieldValue
      end

      implements_node templates: [[:ifnv, :id]], as: "IFNV", ready_date: "1970-01-01" do |issue_field_number_value|
        {
          prefix: :ifnv,
          id: issue_field_number_value.id
        }
      end

      def self.load_from_global_id(id)
        Platform::Loaders::ActiveRecord.load(::IssueFieldNumberValue, id.to_i, security_violation_behaviour: :nil).then do |field_value|
          next unless field_value
          field_value.async_issue.then do
            field_value
          end
        end
      end

      field :value, Float, "Value of the field.", null: false
    end
  end
end
