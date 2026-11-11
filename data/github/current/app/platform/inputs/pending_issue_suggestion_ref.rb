# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class PendingIssueSuggestionRef < Platform::Inputs::Base
      docs_category :issues
      visibility :internal
      description "A reference to a single pending issue suggestion to apply."

      argument :kind, Enums::PendingIssueSuggestionKind, "The kind of suggestion to apply.", required: true
      argument :issue_type_id, ID, "The ID of the suggested issue type. Required when kind is TYPE.", required: false
      argument :label_id, ID, "The ID of the suggested label. Required when kind is LABEL.", required: false
      argument :issue_field_id, ID, "The ID of the suggested issue field. Required when kind is FIELD.", required: false
    end
  end
end
