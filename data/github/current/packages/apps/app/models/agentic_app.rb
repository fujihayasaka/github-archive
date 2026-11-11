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
# - (Deferred) user_token_permissions: Read-only OAuth scopes
# - (Deferred) installation_token_permissions: Write scopes for git/workflow operations
module AgenticApp
  extend T::Helpers
  extend EnterpriseOptInDependency

  AgentInstance = T.type_alias { T.all(::AgenticApp, Object) }
  AgentCollection = T.type_alias { T::Array[AgentInstance] }

  @registry = T.let(nil, T.nilable(AgentCollection))

  interface!

  # Public: Unique slug identifier for this agent (kebab-case)
  # Used for routing, mentions, and telemetry
  sig { abstract.returns(String) }
  def slug; end

  # Public: Human-readable display name
  # Used in UI (assignment selector, autocomplete)
  sig { abstract.returns(String) }
  def display_name; end

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
    registry.dup
  end

  sig { params(agent: AgentInstance).void }
  def self.register_agent(agent)
    current_registry = registry
    return if current_registry.any? { |existing| existing.equal?(agent) }

    @registry = current_registry + [agent]
  end

  sig { params(agent: AgentInstance).void }
  def self.unregister_agent(agent)
    @registry = registry.reject { |existing| existing.equal?(agent) }
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
  # Returns a Hash with:
  #   - token: String in the format "@!display_name" (e.g., "@!Copilot")
  #   - slug: String agent slug for metadata (e.g., "copilot-swe-agent")
  sig { params(agent: AgentInstance).returns({ token: String, slug: String }) }
  def self.mention_token(agent)
    {
      token: "@!#{agent.display_name}",
      slug: agent.slug
    }
  end

  sig { returns(AgentCollection) }
  def self.registry
    @registry ||= default_registry
  end
  private_class_method :registry

  sig { returns(AgentCollection) }
  def self.default_registry
    [
      ::AgenticApp::CopilotAgent.instance,
      ::AgenticApp::ClaudeAgent.instance,
      ::AgenticApp::CodexAgent.instance,
    ]
  end
  private_class_method :default_registry
end
