# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class IssueSearchType < Platform::Enums::Base
      docs_category :issues
      description "Type of issue search performed"

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      value "LEXICAL", "Lexical (keyword-based) search"
      value "SEMANTIC", "Semantic (meaning-based) search using embeddings"
      value "HYBRID", "Hybrid search combining lexical and semantic approaches"
    end
  end
end
