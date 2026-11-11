# typed: strict
# frozen_string_literal: true

module Search
  module Queries
    # Represents a similar issue or pull request result with its similarity score.
    #
    # This struct is shared across query classes that return semantically similar items:
    # - SemanticSimilarIssueQuery.find_similar_to
    # - ConditionalIssueSemanticQuery (via controller usage)
    #
    # Both query types inherit from Search::Queries::IssueQuery, making this
    # a natural shared data structure for their results.
    #
    # For pull request results, the `issue` field contains the Issue object
    # that backs the PR (since PRs are modeled as issues internally).
    #
    # @example Creating a result from Elasticsearch response
    #   SimilarIssueResult.new(issue: result["_model"], score: result["_score"])
    #
    # @example Accessing result data
    #   result.issue  # => Issue object (may be a PR-backing issue)
    #   result.score  # => Float or nil
    #
    class SimilarIssueResult < T::Struct
      # The similar Issue object (for PRs, this is the Issue backing the PR)
      const :issue, Issue

      # The similarity score from Elasticsearch (may be nil if unavailable).
      # Higher scores indicate greater similarity. The specific scoring formula
      # varies by query class (e.g., SemanticSimilarIssueQuery uses weighted
      # title/body semantic similarity, while ConditionalIssueSemanticQuery
      # uses different weighting factors).
      const :score, T.nilable(Float)
    end
  end
end
