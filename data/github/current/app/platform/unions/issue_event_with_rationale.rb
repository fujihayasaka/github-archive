# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class IssueEventWithRationale < Platform::Unions::Base
      docs_category :issues
      description "An issue timeline event that may have an associated rationale."

      visibility :under_development

      possible_types(
        Objects::IssueTypeAddedEvent,
        Objects::IssueTypeRemovedEvent,
        Objects::IssueTypeChangedEvent,
        Objects::IssueFieldAddedEvent,
        Objects::IssueFieldRemovedEvent,
        Objects::IssueFieldChangedEvent,
        Objects::LabeledEvent,
        Objects::UnlabeledEvent,
      )

      def self.resolve_type(object, context)
        case object.event
        when "issue_type_added"
          Objects::IssueTypeAddedEvent
        when "issue_type_removed"
          Objects::IssueTypeRemovedEvent
        when "issue_type_changed"
          Objects::IssueTypeChangedEvent
        when "issue_field_added"
          Objects::IssueFieldAddedEvent
        when "issue_field_removed"
          Objects::IssueFieldRemovedEvent
        when "issue_field_changed"
          Objects::IssueFieldChangedEvent
        when "labeled"
          Objects::LabeledEvent
        when "unlabeled"
          Objects::UnlabeledEvent
        else
          raise Platform::Errors::Internal, "Unknown issue type event: #{object.event}"
        end
      end
    end
  end
end
