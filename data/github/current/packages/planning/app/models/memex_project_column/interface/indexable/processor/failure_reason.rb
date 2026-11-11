# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable::Processor
  # Processors can fail for various reasons. This class encapsulates the reasons
  # we expect that processing would fail.
  class FailureReason
    COMBINED_SET = T.let([
      CONTENT_MISSING = "content-missing",
      FEATURE_FLAG_SKIPPED = "feature-flag-skipped",
      MAX_ASSOCIATIONS_EXCEEDED = "max-associations-exceeded",
      MESSAGE_IGNORED = "message-ignored",
      NO_MATCHING_DOCS = "no-matching-documents",
      PARTIAL_RESYNC = "partial-resync",
      PROJECT_MISSING = "project-missing",
    ], T::Array[String])

    sig { params(failure_reason: T.nilable(String)).returns(T::Boolean) }
    def self.invalid?(failure_reason)
      return false unless failure_reason.present?

      !COMBINED_SET.include?(failure_reason)
    end
  end
end
