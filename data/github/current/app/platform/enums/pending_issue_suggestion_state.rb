# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PendingIssueSuggestionState < Platform::Enums::Base
      docs_category :issues
      description "The state of a pending issue suggestion."

      visibility :internal

      value "PENDING", "The suggestion has not yet been applied or rejected.", value: ::Issues::PendingTypeSuggestion::STATE_PENDING
      value "APPLIED", "The suggestion has been applied to the issue.", value: ::Issues::PendingTypeSuggestion::STATE_APPLIED
      value "REJECTED", "The suggestion has been rejected.", value: ::Issues::PendingTypeSuggestion::STATE_REJECTED
    end
  end
end
