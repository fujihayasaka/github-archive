# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module IssueFieldValueCommon
      include Platform::Interfaces::Base
      description "Common fields across different issue field value types"

      visibility :under_development

      field :field, Platform::Unions::IssueFields,  description: "The issue field that contains this value.", null: false
      def field
        @object.async_issue_field
      end
    end
  end
end
