# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class RuleEnforcementOptionsMenuComponent < ApplicationComponent
    sig { params(form: T.untyped, rule: VulnerabilityAlertRule, target: T.any(User, Repository)).void }
    def initialize(form:, rule:, target:)
      @form = form
      @target = target
      @rule = rule
    end

    sig { returns(String) }
    def caption
      return "" unless @target.is_a?(User)

      if @target.advanced_security_purchased?
        "Rules will target all public repositories and private repositories with GitHub Advanced Security enabled in this organization."
      elsif @target.plan.business_plus?
        safe_join([
          "Rules will target all public repositories in this organization. To target private repositories, upgrade to ",
          link_to(
              "GitHub Advanced Security",
              "#{GitHub.help_url}/enterprise-cloud@latest/billing/managing-billing-for-github-advanced-security/signing-up-for-github-advanced-security",
              class: "Link--inTextBlock",
            ),
          "."
        ])
      else
        "Rules will target all public repositories in this organization."
      end
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def options
      # Calculate enablement of this rule in the context of the given target.
      # If the rule is new and has no enablement behavior yet, use :enabled.
      enablement = @rule.enablement ? @rule.enablement_for_target(@target) : VulnerabilityAlertRule::Enablement::EnabledByDefault

      if @target.is_a?(User)
        adjective = @target.advanced_security_purchased? ? "eligible" : "public"
        [
          {
            label: "Enabled",
            description: "Rule is enabled by default for all #{adjective} repositories.",
            value: VulnerabilityAlertRule::Enablement::EnabledByDefault.name,
            active: (enablement.enabled? && enablement.unforced?),
          },
          {
            label: "Enforced",
            description: "Rule is enabled for all #{adjective} repositories and can never be disabled by individual repositories.",
            value: VulnerabilityAlertRule::Enablement::ForceEnabled.name,
            active: (enablement.enabled? && enablement.forced?),
          },
          {
            label: "Disabled",
            description: "Rule can never be enabled on any repositories.",
            value: VulnerabilityAlertRule::Enablement::ForceDisabled.name,
            active: enablement.disabled?,
          },
        ]
      else
        [
          {
            label: "Enabled",
            description: "",
            value: VulnerabilityAlertRule::Enablement::EnabledByDefault.name,
            active: enablement.enabled?,
          },
          {
            label: "Disabled",
            description: "",
            value: VulnerabilityAlertRule::Enablement::DisabledByDefault.name,
            active: enablement.disabled?,
          },
        ]
      end
    end
  end
end
