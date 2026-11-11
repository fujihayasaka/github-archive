# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module IssueFieldValueCommon
      include Platform::Interfaces::Base
      description "Common fields across different issue field value types"

      feature_flag :issue_fields

      field :field, Platform::Unions::IssueFields,  description: "The issue field that contains this value.", null: true
      def field
        @object.async_issue_field.then do |issue_field|
          return nil unless issue_field

          Platform::Models::IssueFieldWithIssueContext.new(issue_field, issue: @object.issue)
        end
      end
    end
  end
end
