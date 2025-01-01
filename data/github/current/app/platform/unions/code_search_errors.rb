# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class CodeSearchErrors < Platform::Unions::Base
      description "Possible code search error types"

      required_capabilities [:mobile_only_schema_mask]

      possible_types(
        Objects::CodeSearchActorNotAuthorizedError,
        Objects::CodeSearchInaccessibleRepoError,
        Objects::CodeSearchIncompleteResultsError,
        Objects::CodeSearchInconsistentResultsError,
        Objects::CodeSearchQueryParsingFatalError,
        Objects::CodeSearchQueryParsingWarningError,
        Objects::CodeSearchScopeUnsatisfiableError,
        Objects::CodeSearchTimeoutError,
        Objects::CodeSearchUnspecifiedError,
      )
    end
  end
end
