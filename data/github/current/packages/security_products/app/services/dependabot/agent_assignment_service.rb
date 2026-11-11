# typed: strict
# frozen_string_literal: true

module Dependabot
  # Shared service for Dependabot alert agent assignment logic.
  # Used by both the Rails controller (AgentAssignmentsController) and
  # the Sinatra API (RepositoryDependabotAlerts) to avoid duplication.
  class AgentAssignmentService
    class Error < StandardError
      sig { returns(Symbol) }
      attr_reader :error_kind

      sig { params(message: String, error_kind: Symbol).void }
      def initialize(message, error_kind)
        super(message)
        @error_kind = T.let(error_kind, Symbol)
      end
    end

    # Resolves and validates the agent for assignment.
    # Returns [agent, bot] or raises Error.
    sig do
      params(
        agent_id: T.nilable(Integer),
        repo: Repository,
        user: User,
      ).returns([T.all(AgenticApp, Object), Bot, Integration])
    end
    def resolve_agent!(agent_id:, repo:, user:)
      agent = if agent_id
        AgenticApp.agent_for_integration_id(agent_id)
      else
        AgenticApp::CopilotAgent.instance
      end

      raise Error.new("No agent found for the given agent_id", :agent_not_found) unless agent

      if FeatureFlag.vexi.enabled?(:filter_non_assignable_agent_bots, repo, default: false)
        unless agent.assignable?
          GitHub.logger.info({
            body: "[Copilot-Assign] Rejected non-assignable agent in Dependabot alerts path",
            agent_class: agent.class.name,
            agent_slug: agent.respond_to?(:slug) ? agent.slug : nil,
            repository_id: repo.id,
            actor_id: user.id,
          })
          GitHub.dogstats.increment("dependabot_alerts.copilot.agent_not_assignable")
          raise Error.new("Agent is not assignable", :agent_not_assignable)
        end
      end

      app = agent.integration
      raise Error.new("Agent integration not found", :agent_not_found) unless app

      bot = app.bot
      raise Error.new("Agent bot not found", :agent_not_found) unless bot

      [agent, T.cast(bot, Bot), app]
    end

    # Validates target repository for cross-repo agent assignment.
    sig do
      params(
        target_repo: Repository,
        source_repo: Repository,
        agent: T.all(AgenticApp, Object),
        user: User,
      ).void
    end
    def validate_target_repo!(target_repo:, source_repo:, agent:, user:)
      if target_repo != source_repo
        unless agent.enabled_for_repository?(target_repo, user)
          raise Error.new("Agent is not enabled for the target repository", :agent_not_enabled)
        end

        unless target_repo.writable_by?(user)
          raise Error.new("Not Found", :target_repo_not_found)
        end
      end

      if target_repo.archived?
        raise Error.new("Cannot assign the agent to alerts in archived repositories.", :target_repo_archived)
      end
    end

    # Builds assignment attributes from normalized parameters.
    sig do
      params(
        target_repo: Repository,
        agent_id: T.nilable(Integer),
        user: User,
        base_branch: T.nilable(String),
        custom_instructions: T.nilable(String),
        custom_agent: T.nilable(String),
        model: T.nilable(String),
        remote_ip: T.nilable(String),
        skip_pull_request: T.nilable(T::Boolean),
      ).returns(Issues::AgentAssignmentNewAttributes)
    end
    def build_assignment_attributes(target_repo:, agent_id:, user:, base_branch: nil, custom_instructions: nil, custom_agent: nil, model: nil, remote_ip: nil, skip_pull_request: nil)
      base_ref = base_branch.presence || target_repo.default_branch
      resolved_model = if FeatureFlag.vexi.enabled?(:coding_agent_model_selection, user, default: false)
        model
      end

      Issues::AgentAssignmentNewAttributes.new(
        target_repository: target_repo,
        base_ref: base_ref,
        custom_instructions: custom_instructions,
        custom_agent: custom_agent,
        agent_id: agent_id,
        remote_ip: remote_ip,
        model: resolved_model,
        skip_pull_request: skip_pull_request == true,
      )
    end

    # Executes the Copilot assignment, wrapping CAPI errors into service errors.
    sig do
      params(
        alert: RepositoryVulnerabilityAlert,
        user: User,
        token: ::Copilot::Token,
        attributes: Issues::AgentAssignmentNewAttributes,
        failbot_context: String,
      ).returns(T.untyped)
    end
    def execute_assignment!(alert:, user:, token:, attributes:, failbot_context:)
      alert.assign_to_copilot(user, token, attributes)
    rescue CopilotAPI::NotFoundError
      raise Error.new("The agent was not found in this repository.", :copilot_forbidden)
    rescue CopilotAPI::UnauthorizedError
      raise Error.new("Please check that you have permission to assign in the target repository.", :copilot_forbidden)
    rescue StandardError => e
      if CopilotSweAgentJobHelper.timeout_error?(e)
        raise Error.new("Failed to assign the agent after multiple retries. Please try again later.", :copilot_timeout)
      else
        Failbot.report(e, {
          app: "github",
          feature: "dependabot_alert_copilot_assign",
          context: failbot_context,
        })
        raise Error.new(
          "Something went wrong while assigning the agent. Please try again later, or contact support if the problem persists.",
          :copilot_unexpected,
        )
      end
    end
  end
end
