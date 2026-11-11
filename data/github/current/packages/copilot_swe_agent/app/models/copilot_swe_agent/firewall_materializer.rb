# typed: strict
# frozen_string_literal: true

module CopilotSweAgent
  # Single source of truth for firewall configuration materialization.
  # Produces the final, combined firewall payload for a repository by resolving
  # the hierarchy: Enterprise → Organization → Repository.
  #
  # Org-level config (booleans + allowlist) comes from Configurable + FirewallAllowlist.
  # Repo-level config comes from Variables (COPILOT_AGENT_FIREWALL_*) — stored
  # under the agents app when `actions_agent_secrets` is enabled, otherwise
  # under the actions app.
  #
  # Resolution logic per setting:
  # - enabled: org policy overrides repo when non-nil; nil defers to repo
  # - use_default_rules: org policy overrides repo when non-nil; nil defers to repo
  # - If org explicitly disables firewall → firewall off, no rules
  # - allowlist rules: enterprise + org rules always included; repo rules included
  #   only when org allows custom rules (true) or has no policy (nil)
  class FirewallMaterializer
    MaterializedConfig = T.type_alias do
      {
        enabled: T::Boolean,
        use_default_rules: T::Boolean,
        rules: T::Array[String],
      }
    end

    sig { params(repository: ::Repository, actor: ::User).returns(MaterializedConfig) }
    def self.materialize(repository, actor)
      new(repository, actor).materialize
    end

    sig { params(repository: ::Repository, actor: ::User).void }
    def initialize(repository, actor)
      @repository = repository
      @actor = actor
      @organization = T.let(repository.owner, T.nilable(::User))
    end

    sig { returns(MaterializedConfig) }
    def materialize
      org = @organization
      unless org.is_a?(::Organization)
        return repo_config
      end

      # Read nullable org policies — nil means "no policy, defer to repo"
      org_enabled_policy = org.copilot_swe_agent_firewall_enabled_policy
      org_use_default_rules_policy = org.copilot_swe_agent_firewall_use_default_rules_policy
      org_allow_custom_rules_policy = org.copilot_swe_agent_firewall_allow_custom_rules_policy

      # If org explicitly disabled firewall, it's off regardless of repo
      if org_enabled_policy == false
        return { enabled: false, use_default_rules: false, rules: [] }
      end

      # Gather org-level and enterprise-level allowlist rules
      org_allowlist = CopilotSweAgent::FirewallAllowlist.for(org)
      org_rules = org_allowlist&.rules || []

      enterprise_rules = if org.business.present?
        enterprise_allowlist = CopilotSweAgent::FirewallAllowlist.for(T.must(org.business))
        enterprise_allowlist&.rules || []
      else
        []
      end

      # Start with repo config as baseline
      repo = repo_config

      # Resolve each setting: org policy overrides repo when non-nil, defers when nil
      enabled = org_enabled_policy.nil? ? repo[:enabled] : org_enabled_policy
      use_default_rules = org_use_default_rules_policy.nil? ? repo[:use_default_rules] : org_use_default_rules_policy

      # For rules: if org allows custom rules (or has no policy), include repo rules
      include_repo_rules = org_allow_custom_rules_policy.nil? || org_allow_custom_rules_policy
      repo_rules = include_repo_rules ? repo[:rules] : []

      combined_rules = (enterprise_rules + org_rules + repo_rules).uniq

      {
        enabled: enabled,
        use_default_rules: use_default_rules,
        rules: combined_rules,
      }
    end

    private

    # Reads the repo-level firewall configuration from Variables (agents or
    # actions app, depending on the `actions_agent_secrets` feature flag).
    sig { returns(MaterializedConfig) }
    def repo_config
      @repo_config ||= T.let(read_repo_firewall_variables, T.nilable(MaterializedConfig))
    end

    sig { returns(MaterializedConfig) }
    def read_repo_firewall_variables
      variables_app = Variables::AppsHelper.app_for_repo_firewall(@actor, @repository)

      # If neither the agents nor the actions app is available, use safe defaults
      return { enabled: true, use_default_rules: true, rules: [] } if variables_app.nil?

      response = Variables.for_app_paginated(
        variables_app,
        owner: @repository,
        actor: @actor,
        page: 1,
        per_page: 1000,
      )

      return { enabled: true, use_default_rules: true, rules: [] } if response.blank?

      vars = response[:variables].to_h do |variable|
        [variable.name, Base64.strict_decode64(variable.value)]
      end

      enabled_val = vars["COPILOT_AGENT_FIREWALL_ENABLED"]
      allow_list = vars["COPILOT_AGENT_FIREWALL_ALLOW_LIST"]
      allow_list_additions = vars["COPILOT_AGENT_FIREWALL_ALLOW_LIST_ADDITIONS"]

      # Validate COPILOT_AGENT_FIREWALL_ENABLED is only "true" or "false"
      if enabled_val.present? && enabled_val != "true" && enabled_val != "false"
        GitHub.logger.warn("FirewallMaterializer: Invalid COPILOT_AGENT_FIREWALL_ENABLED value '#{enabled_val}' for repo #{@repository.id}, defaulting to enabled")
        return { enabled: true, use_default_rules: true, rules: [] }
      end

      # Validate that both allowlist variables are not set simultaneously
      if allow_list.present? && allow_list_additions.present?
        GitHub.logger.warn("FirewallMaterializer: Both ALLOW_LIST and ALLOW_LIST_ADDITIONS set for repo #{@repository.id}, defaulting to enabled with default rules")
        return { enabled: true, use_default_rules: true, rules: [] }
      end

      use_default_rules = !vars.key?("COPILOT_AGENT_FIREWALL_ALLOW_LIST")
      rules_str = use_default_rules ? allow_list_additions : allow_list
      rules = rules_str&.split(",")&.map(&:strip)&.reject(&:blank?) || []

      {
        enabled: (enabled_val || "true") == "true",
        use_default_rules: use_default_rules,
        rules: rules,
      }
    rescue Variables::Error => e
      # Variables API errors (service unavailable, network issues, etc.).
      # Fall back to safe defaults — firewall enabled with recommended allowlist.
      GitHub.logger.warn("FirewallMaterializer: Failed to read variables for repo #{@repository.id}: #{e.message}")
      { enabled: true, use_default_rules: true, rules: [] }
    end
  end
end
