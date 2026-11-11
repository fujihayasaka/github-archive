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

  # todo(shaikhul) - we need to find a better way
  AGENT_SOURCE_LIMIT = 100

  @registry = T.let(nil, T.nilable(AgentCollection))

  # Per-request cache to avoid redundant DB queries when multiple
  # code paths call all_agents within the same request.
  class RequestCache < ActiveSupport::CurrentAttributes
    attribute :agents
  end

  interface!

  # Public: Unique slug identifier for this agent (kebab-case)
  # Used for routing, mentions, and telemetry
  sig { abstract.returns(String) }
  def slug; end

  # Public: Human-readable display name
  # Used in UI (assignment selector, autocomplete)
  sig { abstract.returns(String) }
  def display_name; end

  # Public: Display owner name for this agent
  # Used in UI descriptions (e.g., "GitHub", "Anthropic", "OpenAI")
  sig { abstract.returns(String) }
  def display_owner; end

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
      viewer: T.untyped
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
  end

  # Public: Find an agent by slug
  #
  # slug - String slug identifier
  #
  # Returns AgenticApp instance or nil
  sig { params(slug: String).returns(T.nilable(AgentInstance)) }
  def self.agent_for_slug(slug)
    all_agents.find { |agent| agent.slug == slug }
  end

  sig { params(bot_id: T.untyped).returns(T.nilable(T.all(AgenticApp, Object))) }
  def self.agent_for_bot_id(bot_id)
    all_agents.find { |agent| agent.bot_id == bot_id }
  end

  sig { params(integration_id: T.untyped).returns(T.nilable(T.all(AgenticApp, Object))) }
  def self.agent_for_integration_id(integration_id)
    all_agents.find { |agent| agent.integration&.id == integration_id }
  end

  # Public: Returns the mention token for an agent
  # Used for @-mentions in comments and PR descriptions
  #
  # agent - An AgenticApp instance
  #
  # Returns a String in the format "@display_name[agent]" (e.g., "@claude[agent]")
  # For copilot we return "@copilot" to match existing behavior
  sig { params(agent: AgentInstance).returns(String) }
  def self.mention_token(agent)
    return agent.display_name.downcase if agent == ::AgenticApp::CopilotAgent.instance

    "#{agent.display_name.downcase}[agent]"
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
      next if source.integration.nil?
      next if hardcoded_integration_ids.include?(source.integration_id)

      ThirdPartyAgent.new(source)
    end
  end

  sig { params(bot: T.nilable(Bot)).returns(T.nilable(AgentInstance)) }
  def self.agent_for_bot(bot)
    return nil unless bot
    all_agents.find { |agent| agent.bot_id == bot.id }
  end

  private_class_method :default_registry
  private_class_method :integration_source_agents
end
