# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module IssueFieldValueCommon
      include Platform::Interfaces::Base
      description "Common fields across different issue field value types"


      field :field, Platform::Unions::IssueFields,  description: "The issue field that contains this value.", null: true
      def field
        @object.async_issue_field.then do |issue_field|
          if ::FeatureFlag.vexi.enabled?(:fix_bad_return_issue_field_value, default: false)
            next nil unless issue_field
          else
            return nil unless issue_field # rubocop:disable GitHub/DontReturnInsidePromiseThen
          end

          Platform::Models::IssueFieldWithIssueContext.new(issue_field, issue: @object.issue)
        end
      end
    end
  end
end
