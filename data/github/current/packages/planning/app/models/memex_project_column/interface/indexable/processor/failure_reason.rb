# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable::Processor
  # Processors can fail for various reasons. This class encapsulates the reasons
  # we expect that processing would fail.
  class FailureReason

    COMBINED_SET = T.let([
      NO_MATCHING_DOCS = "no-matching-documents",
      CONTENT_MISSING = "content-missing",
      PROJECT_MISSING = "project-missing",
      MESSAGE_IGNORED = "message-ignored",
      PARTIAL_RESYNC = "partial-resync",
    ], T::Array[String])

    sig { params(failure_reason: T.nilable(String)).returns(T::Boolean) }
    def self.invalid?(failure_reason)
      return false unless failure_reason.present?

      !COMBINED_SET.include?(failure_reason)
    end
  end
end
