# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class LexicalFallbackReason < Platform::Enums::Base
      docs_category :search
      description "Reason why a semantic or hybrid issue search fell back to lexical search"

      visibility :public, environments: [:dotcom]

      value "QUOTED_TEXT", "Query contains quoted text requiring exact matches"
      value "NO_TEXT_TERMS", "Query has only qualifiers and no free text terms"
      value "SERVER_ERROR", "Embedding generation failed or timed out"
      value "ONLY_NON_SEMANTIC_FIELDS_REQUESTED", "Query uses an in: qualifier targeting non-semantic fields"
      value "OR_BOOLEAN_NOT_SUPPORTED", "Query contains OR operators (nested boolean qualifiers)"
      value "NON_ISSUE_TARGET", "Query targets non-issue types (e.g., pull requests)"
      value "NO_ACCESSIBLE_REPOS", "Scoped query resolved to zero accessible repositories"
    end
  end
end
