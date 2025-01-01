# typed: true
# frozen_string_literal: true
module Settings
  class SecurityAnalysisInlineNotificationComponent < ApplicationComponent
    PRODUCTS = {
      advanced_security: "GitHub Advanced Security",
      secret_scanning: "Secret scanning",
      push_protection: "Secret scanning push protection",
      dependency_graph: "Dependency graph",
      dependabot_alerts: "Dependabot alerts",
      dependabot_updates: "Dependabot security updates",
      validity_checks: "Secret scanning validity checks",
      lower_confidence_patterns: "Lower confidence patterns",
      generic_secrets: "AI detection",
    }.freeze

    REASONS = {
      advanced_security_restricted_by_policy: "a GitHub Advanced Security availability enterprise policy",
      advanced_security_restricted_by_enablement_policy: "a GitHub Advanced Security enablement enterprise policy",
      token_scanning_restricted_by_enablement_policy: "a secret scanning enterprise policy",
      advanced_security_restricted_by_secret_scanning_enablement_policy: "a secret scanning enterprise policy",
      advanced_security_backfill_in_progress: "an in-progress backfill",
      vulnerability_alerts_restricted_by_enablement_policy: "a Dependabot alerts enterprise policy",
      feature_not_available_on_archived_or_deleted_repos: "repository has been archived or deleted",
    }.freeze

    TEST_SELECTOR = "security-analysis-inline-enterprise-policy-notification"

    attr_reader :owner, :product_name, :blocked_by, :reason, :variant, :system_arguments
    private :owner, :product_name, :blocked_by, :reason, :variant, :system_arguments

    def initialize(blocked_by, owner:, product:, variant: nil, **system_arguments)
      @owner = owner
      @product_name = PRODUCTS[product] || "This security product's"
      @blocked_by = blocked_by
      @reason = REASONS[blocked_by]
      @variant = variant # a symbol for customizing how the notification is rendered, :short will hide the enterprise suffix and URL
      @system_arguments = system_arguments
    end

    def render?
      reason.present?
    end

    private

    def render_set_by_enterprise_suffix?
      return false if @variant == :short
      blocked_by != :advanced_security_backfill_in_progress && enterprise_name
    end

    def policy_block_url
      return nil if @variant == :short
      section = case @blocked_by
      when :advanced_security_restricted_by_enablement_policy
        "enforcing-a-policy-to-manage-the-use-of-github-advanced-security-features-in-your-enterprises-repositories"
      when :advanced_security_restricted_by_policy
        "enforcing-a-policy-for-the-use-of-github-advanced-security-in-your-enterprises-organizations"
      when :vulnerability_alerts_restricted_by_enablement_policy
        "enforcing-a-policy-to-manage-the-use-of-dependabot-alerts-in-your-enterprise"
      when :advanced_security_restricted_by_secret_scanning_enablement_policy, :token_scanning_restricted_by_enablement_policy
        "enforcing-a-policy-to-manage-the-use-of-secret-scanning-in-your-enterprises-repositories"
      else
        return nil
      end

      "https://docs.github.com/enterprise-cloud@latest/admin/policies/enforcing-policies-for-your-enterprise/enforcing-policies-for-code-security-and-analysis-for-your-enterprise##{section}"
    end

    memoize def enterprise_name
      return unless owner.present?
      return unless owner.is_a?(::Organization)
      return if owner.business.nil?
      owner.business&.name
    end
  end
end
