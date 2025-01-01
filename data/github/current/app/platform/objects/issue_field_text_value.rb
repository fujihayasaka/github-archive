# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class IssueFieldTextValue < Platform::Objects::Base
      implements Platform::Interfaces::IssueFieldValueCommon

      description "The value of a text field in an Issue item."
      visibility :under_development

      class << self
        # Delegate static methods to the IssueFieldValue helper.
        delegate :async_api_can_access?, to: Platform::Helpers::IssueFieldValue
        delegate :async_viewer_can_see?, to: Platform::Helpers::IssueFieldValue
      end

      implements_node templates: [[:iftv, :id]], as: "IFTV", ready_date: "1970-01-01" do |issue_field_text_value|
        {
          prefix: :iftv,
          id: issue_field_text_value.id
        }
      end

      field :value, String, "Value of the field.", null: false
    end
  end
end
