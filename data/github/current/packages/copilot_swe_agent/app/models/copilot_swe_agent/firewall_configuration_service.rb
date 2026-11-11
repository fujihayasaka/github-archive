# typed: strict
# frozen_string_literal: true

module CopilotSweAgent
  # Service object that orchestrates firewall configuration updates for an organization.
  # Handles updating boolean policy flags, persisting allowlist rules, and emitting audit events.
  class FirewallConfigurationService
    sig { params(organization: ::Organization).void }
    def initialize(organization)
      @organization = organization
    end

    # Returns the full firewall configuration including nullable policy values and allowlist rules.
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def config
      allowlist = CopilotSweAgent::FirewallAllowlist.for(@organization)
      {
        enabled: @organization.copilot_swe_agent_firewall_enabled_policy,
        useDefaultRules: @organization.copilot_swe_agent_firewall_use_default_rules_policy,
        allowCustomRules: @organization.copilot_swe_agent_firewall_allow_custom_rules_policy,
        rules: allowlist&.rules || [],
      }
    end

    # Updates the firewall configuration: policy flags (nullable) and optionally allowlist rules.
    # Pass nil for a policy value to clear it ("No policy" / defer to repo).
    # Raises ActiveRecord::RecordInvalid if rules fail model validation.
    sig do
      params(
        enabled: T.nilable(T::Boolean),
        use_default_rules: T.nilable(T::Boolean),
        allow_custom_rules: T.nilable(T::Boolean),
        actor: ::User,
        rules: T.nilable(T::Array[String]),
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def update(enabled:, use_default_rules:, allow_custom_rules:, actor:, rules: nil)
      @organization.update_copilot_swe_agent_firewall(
        enabled: enabled,
        use_default_rules: use_default_rules,
        allow_custom_rules: allow_custom_rules,
        actor: actor,
      )

      update_allowlist_rules(actor: actor, rules: rules) unless rules.nil?

      config
    end

    private

    sig { params(actor: ::User, rules: T::Array[String]).void }
    def update_allowlist_rules(actor:, rules:)
      sanitized_rules = rules.map(&:strip).reject(&:blank?)

      if sanitized_rules.empty?
        allowlist = CopilotSweAgent::FirewallAllowlist.find_by(
          resource_type: "User",
          resource_id: @organization.id,
        )
        if allowlist
          allowlist.destroy!
          Copilot::Instrumenter.instrument_swe_agent_firewall_allowlist_updated(
            resource: @organization,
            actor: actor,
            rules: [],
          )
        end
        return
      end

      allowlist = CopilotSweAgent::FirewallAllowlist.find_or_initialize_by(
        resource_type: "User",
        resource_id: @organization.id,
      )
      allowlist.organization_id = @organization.id
      allowlist.rules = sanitized_rules
      allowlist.updated_by = actor
      allowlist.save!

      Copilot::Instrumenter.instrument_swe_agent_firewall_allowlist_updated(
        resource: @organization,
        actor: actor,
        rules: sanitized_rules,
      )
    end
  end
end
