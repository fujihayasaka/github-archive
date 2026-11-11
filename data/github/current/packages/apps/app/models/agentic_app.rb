# typed: strict
# frozen_string_literal: true

# Sorbet interface for AI coding agents (GitHub-owned and partner-owned)
# that provides a consistent contract for identity, authorization, and
# enablement semantics.
#
# This abstraction bridges v1 (subclass-based with hardcoded capabilities) to v2
# (data-driven platform with self-service onboarding). Call sites interact with
# stable capability predicates rather than individual app implementations.
#
# Key Methods:
# - slug: Unique identifier for routing/UI
# - display_name: Human-readable label
# - doc_url: Documentation link
# - integration: Returns the Integration instance
# - bot_id: Bot user id for write operations
# - assignable?: Can be assigned to issues/PRs
# - mentionable?: Appears in @ mention autocomplete
# - global?: Differentiates global (Copilot SWE) from installed (partners)
# - enabled_for_repository?(repo, viewer): Central enablement gate
# - installed_for_target?(target): Checks if installed for user/org
# - can_be_enabled_for?(target): Eligibility for enablement
# - partner_agent?: Differentiates between partner agents like (Claude/Codex) or regular 3p apps

# - (Deferred) user_token_permissions: Read-only OAuth scopes
# - (Deferred) installation_token_permissions: Write scopes for git/workflow operations
module AgenticApp
  extend T::Helpers
  extend EnterpriseOptInDependency
  extend PermissionsDependency

  AgentInstance = T.type_alias { T.all(::AgenticApp, Object) }
  AgentCollection = T.type_alias { T::Array[AgentInstance] }

  # Categorizes agents for filtering in the UI.
  class Group < T::Enum
    enums do
      CLOUD = new("cloud")
      CLI = new("cli")
      REVIEW = new("review")
      AUTOMATION = new("automation")
    end
  end

  # todo(shaikhul) - we need to find a better way
  AGENT_SOURCE_LIMIT = 100

  @registry = T.let(nil, T.nilable(AgentCollection))

  # Per-request cache to avoid redundant DB queries when multiple
  # code paths call all_agents within the same request.
  class RequestCache < ActiveSupport::CurrentAttributes
    attribute :agents, :integrations, :integration_installations
  end

  interface!

  # Public: Unique slug identifier for this agent (kebab-case)
  # Used for routing, mentions, and telemetry
  sig { abstract.returns(String) }
  def slug; end

  # Public: The identifier used in @-mention tokens (e.g., "@claude[agent]")
  # Defaults to display_name.downcase for hardcoded agents.
  # DB-backed agents override this to use the integration slug (which is URL-safe).
  sig { abstract.returns(String) }
  def mention_slug; end

  # Public: Human-readable display name
  # Used in UI (assignment selector, autocomplete)
  sig { abstract.returns(String) }
  def display_name; end

  # Public: Display owner name for this agent
  # Used in UI descriptions (e.g., "GitHub", "Anthropic", "OpenAI")
  sig { abstract.returns(String) }
  def display_owner; end

  # Public: The primary model vendor for this agent (e.g., "anthropic", "openai").
  # Returns nil for agents that are not vendor-specific (e.g., Copilot).
  sig { abstract.returns(T.nilable(String)) }
  def model_vendor; end

  # Public: The model vendor identifiers for this agent.
  # Matches the `vendor` field on CodingAgentModel (e.g., "anthropic", "openai").
  # Returns an empty array for agents that support all vendors (e.g., Copilot).
  sig { abstract.returns(T::Array[String]) }
  def model_vendors; end

  # Public: Commit email for this agent
  # Used for commit attribution
  sig { abstract.returns(String) }
  def commit_email; end

  # Public: Documentation URL for this agent
  # Used to provide help/documentation links in UI
  sig { abstract.returns(String) }
  def doc_url; end

  # Public: Returns the Integration instance for this agent
  sig { abstract.returns(T.untyped) }
  def integration; end

  # Public: Returns the database id of the Bot user, if available
  sig { abstract.returns(T.nilable(Integer)) }
  def bot_id; end

  # Public: Can this agent be assigned to issues/PRs like a user?
  # May return false for experimental/testing agents
  sig { abstract.returns(T::Boolean) }
  def assignable?; end

  # Public: Should this agent appear in @ mention autocomplete?
  sig { abstract.returns(T::Boolean) }
  def mentionable?; end

  # Public: Is this a global agent (no installation required)?
  # Only Copilot SWE Agent returns true; all partners return false
  sig { abstract.returns(T::Boolean) }
  def global?; end

  # Public: Is this a partner agent or regular 3p app
  sig { abstract.returns(T::Boolean) }
  def partner_agent?; end

  # Public: Agent group for filtering (e.g., Group::CLOUD, Group::CLI)
  sig { abstract.returns(Group) }
  def group; end

  # Public: Should finished-session notifications be sent for this agent?
  sig { abstract.returns(T::Boolean) }
  def finished_notifications_enabled?; end

  # Public: Is this agent enabled for the given repository and viewer?
  # This is the central enablement gate - must be fast (use caching if needed)
  #
  # repo   - Repository to check enablement for
  # viewer - User requesting the action
  #
  # Returns Boolean
  sig { abstract.params(repo: T.untyped, viewer: T.untyped).returns(T::Boolean) }
  def enabled_for_repository?(repo, viewer); end
  # Public: Is this agent installed for the given target?
  #
  # target - User or Organization to check installation for
  # Returns Boolean
  sig { abstract.params(target: T.any(User, Organization, Business)).returns(T::Boolean) }
  def installed_for_target?(target); end

  # Public: Does this agent require workflow approval for PRs?
  #
  # Returns Boolean - true if workflows should require approval, false if they can run automatically
  sig { abstract.returns(T::Boolean) }
  def require_workflow_approval_for_prs?; end

  # Public: Can this agent be enabled for the given target?
  #
  # target - User or Organization to check enablement eligibility for
  # Returns Boolean
  sig { abstract.params(target: T.any(User, Organization, Business)).returns(T::Boolean) }
  def can_be_enabled_for?(target); end

  # Public: Registry method to find all agents enabled for a repository
  #
  # repo   - Repository to check
  # viewer - User making the request
  #
  # Returns Array of AgenticApp instances
  sig do
    params(
      repo: T.untyped,
      viewer: T.untyped,
    ).returns(AgentCollection)
  end
  def self.enabled_for_repository(repo, viewer)
    all_agents.select { |agent| agent.enabled_for_repository?(repo, viewer) }
  end

  sig { returns(AgentCollection) }
  def self.all_agents
    RequestCache.agents ||= begin
      agents = registry.dup
      if FeatureFlag.vexi.enabled?(:agentic_app_integration_source, default: false)
        agents + integration_source_agents(agents)
      else
        agents
      end
    end
  end

  sig { returns(T::Array[T.all(AgenticApp, Object)]) }
  def self.partner_agents
    [::AgenticApp::ClaudeAgent.instance, ::AgenticApp::CodexAgent.instance]
  end

  # Public: Checks whether an Integration ID belongs to a known first-party
  # (static/hardcoded) agent. Uses the Privileged Apps Registry for a fast
  # hash lookup with no DB queries.
  #
  # app_id - Integer Integration ID to check.
  #
  # Returns true if the app_id matches any static agent in the registry.
  sig { params(app_id: Integer).returns(T::Boolean) }
  def self.first_party_agent?(app_id)
    registry.any? do |agent|
      next false unless agent.is_a?(AgenticApp::Base)

      Apps::Privileged::Registry.app_id(app_alias: agent.privileged_app_alias, type: "Integration") == app_id
    end
  end

  # Public: Per-partner disable switch. When enabled for a specific integration,
  # the app is blocked from inference and hidden from UI listings.
  #
  # integration - The Integration instance to check.
  #
  # Returns true if the integration is disabled.
  sig { params(integration: Integration).returns(T::Boolean) }
  def self.disabled?(integration)
    FeatureFlag.vexi.enabled?(:agentic_app_disabled, integration, default: false)
  end

  # Public: Determines if the given app should be classified as an AI agent in audit logs
  # based on its association with an agentic app and feature flag status.
  #
  # app - An instance of Integration or OauthApplication to check for AI agent audit eligibility.
  #
  # Returns true if the app should be marked as an AI agent in audit logs, false otherwise.
  sig { params(app: T.nilable(T.any(Integration, OauthApplication, PlatformTypes::App))).returns(T::Boolean) }
  def self.ai_agent_for_audit_events_for_app?(app)
    return false unless app.is_a?(Integration)

    return false unless FeatureFlag.vexi.enabled?(:agentic_app_ai_agent_for_audit_events, default: false)

    agent_for_integration_id(app.id).present?
  end

  # Public: Determines if the given app should display an "AI" identifier tag based on its association with an agentic app and feature flag status.
  #
  # app - An instance of Integration or OauthApplication to check for AI identifier display eligibility.
  #
  # Returns true if the app should display an "AI" identifier tag, false otherwise.
  sig { params(app: T.nilable(T.any(Integration, OauthApplication, PlatformTypes::App))).returns(T::Boolean) }
  def self.display_ai_identifier_for_app?(app)
    return false unless app.is_a?(Integration)

    return false unless FeatureFlag.vexi.enabled?(:agentic_app_display_ai_identifier, default: false)

    agent_for_integration_id(app.id).present?
  end

  sig { params(app: T.nilable(T.any(Integration, OauthApplication, PlatformTypes::App))).returns(T::Boolean) }
  def self.ai_agent_blockable_by_enterprise_policy_for_app?(app)
    return false unless app.is_a?(Integration)

    if FeatureFlag.vexi.enabled?(:agentic_app_blockable_by_enterprise_policy, default: false)
      agent = agent_for_integration_id(app.id)
      return false unless agent

      # Currently only partner agents (Codex, Claude) can be blocked by enterprise policy.
      # If this diverges from partner_agent? in the future, add a dedicated method.
      agent.partner_agent?
    else
      Apps::Privileged.capable?(:ai_agent_blockable_by_enterprise_policy, app: app)
    end
  end

  sig { params(agent: AgentInstance).void }
  def self.register_agent(agent)
    current_registry = registry
    return if current_registry.any? { |existing| existing.equal?(agent) }

    @registry = current_registry + [agent]
    RequestCache.agents = nil
  end

  sig { params(agent: AgentInstance).void }
  def self.unregister_agent(agent)
    @registry = registry.reject { |existing| existing.equal?(agent) }
    RequestCache.agents = nil
  end

  sig do
    type_parameters(:Result)
      .params(agent: AgentInstance, blk: T.proc.returns(T.type_parameter(:Result)))
      .returns(T.type_parameter(:Result))
  end
  def self.with_temporary_agent(agent, &blk)
    register_agent(agent)
    blk.call
  ensure
    unregister_agent(agent)
  end

  sig { void }
  def self.reset_registry!
    @registry = nil
    RequestCache.agents = nil
    RequestCache.integrations = nil
    RequestCache.integration_installations = nil
  end

  # Public: Find an agent by its slug identifier
  #
  # slug - String slug (e.g., "copilot-swe-agent", "anthropic-code-agent").
  #
  # Returns AgenticApp instance or nil
  sig { params(slug: String).returns(T.nilable(AgentInstance)) }
  def self.agent_for_slug(slug)
    all_agents.find { |agent| agent.slug == slug }
  end

  # Public: Find an agent by its mentionable slug (the token used in @-mentions)
  #
  # mention_slug - String mention slug to look up (e.g., "copilot", "claude").
  #               Callers are responsible for normalization (e.g., downcasing).
  #
  # Lookup order:
  # 1. Hardcoded registry by mention_slug
  # 2. DB-backed IntegrationAgentSource (when agentic_app_integration_source enabled)
  #
  # Returns AgenticApp instance or nil
  sig { params(mention_slug: String).returns(T.nilable(AgentInstance)) }
  def self.agent_for_mentionable_slug(mention_slug)
    return nil if mention_slug.blank?

    unless FeatureFlag.vexi.enabled?(:agentic_app_mentionable_slug_lookup, default: false)
      return all_agents.find { |agent| agent.mention_slug == mention_slug }
    end

    registry.find { |agent| agent.mention_slug == mention_slug } ||
      find_integration_source_agent_by_slug(mention_slug)
  end

  sig { params(bot_id: T.untyped).returns(T.nilable(T.all(AgenticApp, Object))) }
  def self.agent_for_bot_id(bot_id)
    return nil if bot_id.nil?

    if FeatureFlag.vexi.enabled?(:agentic_app_lookup_optimization, default: false)
      # Check hardcoded agents via cached integration (avoids full scan)
      registry.each do |agent|
        next unless agent.is_a?(AgenticApp::Base)

        cached_integration = agent.integration
        return agent if cached_integration&.bot_id == bot_id
      end

      # Fall through to dynamic agents
      return all_agents.find { |agent| !agent.is_a?(AgenticApp::Base) && agent.bot_id == bot_id }
    end

    all_agents.find { |agent| agent.bot_id == bot_id }
  end

  sig { params(integration_id: T.untyped).returns(T.nilable(T.all(AgenticApp, Object))) }
  def self.agent_for_integration_id(integration_id)
    return nil if integration_id.nil?

    if FeatureFlag.vexi.enabled?(:agentic_app_lookup_optimization, default: false)
      # Check hardcoded agents via Registry (no DB queries)
      registry.each do |agent|
        next unless agent.is_a?(AgenticApp::Base)

        reg_id = Apps::Privileged::Registry.app_id(app_alias: agent.privileged_app_alias, type: "Integration")
        return agent if reg_id == integration_id
      end

      # Fall through to dynamic agents (ThirdPartyAgent etc.)
      return all_agents.find { |agent| !agent.is_a?(AgenticApp::Base) && agent.integration&.id == integration_id }
    end

    all_agents.find { |agent| agent.integration&.id == integration_id }
  end

  sig { params(group: Group).returns(AgentCollection) }
  def self.agents_for_group(group)
    all_agents.select { |agent| agent.group == group }
  end

  # Public: Returns the mention token for an agent
  # Used for @-mentions in comments and PR descriptions
  #
  # agent - An AgenticApp instance
  #
  # Returns a String in the format "@mention_slug[agent]" (e.g., "@claude[agent]")
  # For copilot we return "@copilot" to match existing behavior
  sig { params(agent: AgentInstance).returns(String) }
  def self.mention_token(agent)
    name = agent.mention_slug
    return name if agent == ::AgenticApp::CopilotAgent.instance

    "#{name}[agent]"
  end

  # Public: Find an agent by mention macro
  # mention_macro - String mention macro (e.g., "@copilot", "@claude[agent]")
  #
  # Returns AgenticApp instance or nil
  sig { params(mention_macro: T.untyped).returns(T.nilable(T.all(AgenticApp, Object))) }
  def self.agent_for_mention_macro(mention_macro)
    normalized_macro = mention_macro.delete_prefix("@").downcase
    all_agents.find do |agent|
      AgenticApp.mention_token(agent) == normalized_macro
    end
  end

  sig { returns(AgentCollection) }
  def self.registry
    @registry ||= default_registry
  end
  private_class_method :registry

  sig { returns(AgentCollection) }
  def self.default_registry
    T.let([
      ::AgenticApp::CopilotAgent.instance,
      ::AgenticApp::ClaudeAgent.instance,
      ::AgenticApp::CodexAgent.instance,
      ::AgenticApp::CopilotCodeReviewAgent.instance,
      ::AgenticApp::CodeScanningAgent.instance,
      ::AgenticApp::CliAgent.instance,
    ], AgentCollection)
  end

  # Public: Returns all IntegrationAgentSource records with their integrations.
  sig { returns(T::Array[Copilot::IntegrationAgentSource]) }
  def self.all_agent_sources
    Copilot::IntegrationAgentSource
      .includes(:repository, integration: [:owner, :bot])
      .limit(AGENT_SOURCE_LIMIT)
      .to_a
  end

  # Builds ThirdPartyAgent adapters for data-driven agents that are
  # not already represented by a hardcoded singleton in the registry.
  sig { params(hardcoded: AgentCollection).returns(AgentCollection) }
  def self.integration_source_agents(hardcoded)
    hardcoded_integration_ids = hardcoded.filter_map { |agent| agent.integration&.id }.to_set

    all_agent_sources.filter_map do |source|
      integration = source.integration
      next if integration.nil?
      next if hardcoded_integration_ids.include?(source.integration_id)
      next if disabled?(integration)

      ThirdPartyAgent.new(source)
    end
  end

  sig { params(bot: T.nilable(Bot)).returns(T.nilable(AgentInstance)) }
  def self.agent_for_bot(bot)
    return nil unless bot
    all_agents.find { |agent| agent.bot_id == bot.id }
  end

  sig { params(mention_slug: String).returns(T.nilable(AgentInstance)) }
  def self.find_integration_source_agent_by_slug(mention_slug)
    return nil unless FeatureFlag.vexi.enabled?(:agentic_app_integration_source, default: false)

    integration = Integration.includes(:owner, :bot).find_by(slug: mention_slug)
    return nil if integration.nil?
    return nil if disabled?(integration)

    source = Copilot::IntegrationAgentSource.find_by(integration_id: integration.id)
    return nil if source.nil?

    # Pre-assign the already-loaded integration to avoid a cross-DB lazy load
    source.integration = integration

    agent = ThirdPartyAgent.new(source)
    agent.mention_slug.casecmp?(mention_slug) ? agent : nil
  end

  private_class_method :default_registry
  private_class_method :integration_source_agents
  private_class_method :find_integration_source_agent_by_slug
end
