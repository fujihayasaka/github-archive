# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class PendingIssueSuggestion < Platform::Unions::Base
      docs_category :issues
      description "A pending suggestion for an issue. May target the issue's type, labels, or field values."

      visibility :internal

      possible_types(
        Objects::PendingTypeSuggestion,
        Objects::PendingLabelSuggestion,
        Objects::PendingFieldSuggestion,
      )

      def self.resolve_type(object, context)
        if object.key?(:issue_type_id)
          Objects::PendingTypeSuggestion
        elsif object.key?(:label_id)
          Objects::PendingLabelSuggestion
        elsif object.key?(:issue_field_id)
          Objects::PendingFieldSuggestion
        else
          raise Platform::Errors::Internal, "Unknown pending issue suggestion shape: #{object.keys.inspect}"
        end
      end
    end
  end
end
