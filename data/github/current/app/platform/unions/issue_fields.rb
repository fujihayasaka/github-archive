# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class IssueFields < Platform::Unions::Base
      description "Possible issue fields."
      feature_flag :issue_fields

      possible_types(
        Objects::IssueFieldText,
        Objects::IssueFieldSingleSelect,
        Objects::IssueFieldDate,
        Objects::IssueFieldNumber
      )

      def self.resolve_type(object, context)
        case object.data_type
        when "text"
          Objects::IssueFieldText
        when "single_select"
          Objects::IssueFieldSingleSelect
        when "date"
          Objects::IssueFieldDate
        when "number"
          Objects::IssueFieldNumber
        else
          raise Platform::Errors::Internal, "Unknown issue field data type: #{object.data_type}"
        end
      end
    end
  end
end
