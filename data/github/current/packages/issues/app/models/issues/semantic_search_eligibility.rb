# typed: true
# frozen_string_literal: true

module Issues
  module SemanticSearchEligibility
    # Checks if the user or integration is eligible to use semantic search.
    # This does NOT check repository-level flags.
    # Returns true if the user has the feature flag enabled OR the integration is allowed.
    sig do
      params(
        user: T.nilable(User),
        integration: T.untyped,
        call_site: T.nilable(String)
      ).returns(T::Boolean)
    end
    def self.user_or_integration_eligible?(user:, integration:, call_site: nil)
      return false unless user

      user_ff_enabled = FeatureFlag.vexi.enabled?(:semantic_issues_search_api, user, default: false)
      integration_allowed = integration_allowed?(user: user, integration: integration)

      eligible = user_ff_enabled || integration_allowed

      GitHub.logger.info(
        "Semantic search check: user/integration eligibility",
        user_id: user.id,
        integration_slug: integration&.slug,
        user_ff_enabled: user_ff_enabled,
        integration_allowed: integration_allowed,
        eligible: eligible,
        call_site: call_site,
      )

      eligible
    end

    sig do
      params(
        user: T.nilable(User),
        integration: T.untyped
      ).returns(T::Boolean)
    end
    def self.integration_allowed?(user:, integration:)
      return false if integration.nil?

      FeatureFlag.vexi.enabled?(:semantic_issues_search_allow_apps, user, default: false) &&
        FeatureFlag.vexi.enabled?(:semantic_issues_search_app_allowlist, integration, default: false)
    end

    sig { params(user: T.nilable(User)).returns(T::Boolean) }
    def self.can_search_issues_index?(user:)
      return false unless user

      FeatureFlag.vexi.enabled?(:issues_index_semantic_search, user, default: false)
    end
  end
end
