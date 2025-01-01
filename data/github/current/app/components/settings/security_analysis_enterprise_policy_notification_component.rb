# typed: true
# frozen_string_literal: true

module Settings
  class SecurityAnalysisEnterprisePolicyNotificationComponent < ApplicationComponent
    POLICY_BLOCK_TEXT = "has been blocked by an enterprise policy."
    PRODUCTS = {
      advanced_security: "GitHub Advanced Security",
      secret_scanning: "Secret Scanning",
      dependabot_alerts: "Dependabot Alerts"
    }

    attr_reader :owner

    def initialize(owner:, product:)
      @owner = owner
      @product = product
    end

    memoize def enterprise_name
      return unless @owner.present?

      enterprise = if @owner.is_a?(::Organization)
        @owner.business
      elsif @owner.is_a?(Business)
        @owner
      end

      return if enterprise.nil?

      enterprise.name.chomp(".")
    end

    def product_name
      # Provide a generic output in case the product is not recognized
      PRODUCTS[@product] || "this security product"
    end

    def test_selector_name
      case @product
      when :advanced_security
        "ghas-blocked-by-enterprise-policy"
      when :dependabot_alerts
        "dependabot-alerts-blocked-by-enterprise-policy"
      when :secret_scanning
        "secret-scanning-blocked-by-enterprise-policy"
      end
    end

    def policy_block_url
      section =
        case @product
        when :advanced_security
          "enforcing-a-policy-for-the-use-of-github-advanced-security-in-your-enterprises-organizations"
        when :dependabot_alerts
          "enforcing-a-policy-to-manage-the-use-of-dependabot-alerts-in-your-enterprise"
        when :secret_scanning
          "enforcing-a-policy-to-manage-the-use-of-secret-scanning-in-your-enterprises-repositories"
        end

      "https://docs.github.com/enterprise-cloud@latest/admin/policies/enforcing-policies-for-your-enterprise/enforcing-policies-for-code-security-and-analysis-for-your-enterprise##{section}"
    end
  end
end
