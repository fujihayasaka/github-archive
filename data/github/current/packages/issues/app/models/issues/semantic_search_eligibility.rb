# typed: true
# frozen_string_literal: true

module Issues
  module SemanticSearchEligibility
    # Global kill switch for all semantic search and indexing functionality.
    # When disabled, semantic indexing jobs are skipped, and search endpoints
    # fall back to lexical search or return service unavailable errors.
    # This is independent of per-user eligibility flags.
    sig { returns(T::Boolean) }
    def self.semantic_available?
      FeatureFlag.vexi.enabled?(:issues_semantic_available, default: true)
    end

    # Checks if the user is eligible to use semantic search.
    # This does NOT check repository-level flags.
    sig { params(user: T.nilable(User)).returns(T::Boolean) }
    def self.can_search_issues_index?(user:)
      return false unless user
      return false if GitHub.single_tenant_enterprise?

      true
    end

    sig { params(user: T.nilable(User)).returns(T::Boolean) }
    def self.pr_semantic_search_enabled?(user:)
      return false unless user
      return false if GitHub.single_tenant_enterprise?

      FeatureFlag.vexi.enabled?(:semantic_search_prs_rollout, user, default: false)
    end
  end
end
