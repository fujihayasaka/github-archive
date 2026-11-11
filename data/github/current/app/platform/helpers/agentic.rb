# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    # Common helper methods for dealing with Copilot Agent features & CAPI connectivity.
    module Agentic
      # Use this as the main source-of-truth for getting a token you can use for interacting with CAPI.
      sig { returns(Copilot::DecryptedToken) }
      def decrypted_capi_token
        value = @context[:request_token].to_s

        Copilot::DecryptedToken.from(value)
      end

      # Validates bot assignments using the Agentic Apps platform
      def validate_agent_bot_assignments!(bots, repository, actor:)
        # Require triage/write access before proceeding — without this check an unprivileged
        # viewer on a public repo could pass a bot node ID and trigger token generation
        # even though the domain layer would later drop the assignment.
        actor_can_assign = repository.pushable_by?(actor) ||
                           repository.resources.issues.writable_by?(actor) ||
                           Issue::PermissionsDependency.triageable_by_user?(actor, repository)
        unless actor_can_assign
          Kernel.raise Errors::Forbidden.new("You must have triage access to assign agents to issues.")
        end

        enabled_agent_bots = AgenticApp.enabled_for_repository(repository, actor).map(&:bot_id)

        # find bots that are not part of the list of enabled_agents
        disabled_bots = bots.reject { |bot| enabled_agent_bots.include?(bot.id) }

        disabled_bots.each do |bot|
          # Check if this bot is an agentic app
          agentic_app = AgenticApp.agent_for_bot_id(bot.id)
          if agentic_app.nil?
            Kernel.raise Errors::Forbidden.new("Bot does not have access to the repository.")
          end

          if !agentic_app.assignable?
            Kernel.raise Errors::Forbidden.new("Bot cannot be assigned to issues or pull requests.")
          end

          Kernel.raise Errors::Forbidden.new("#{agentic_app.display_name} agent is not enabled in this repository.")
        end
      end

      # Builds Copilot agent assignment attributes from mutation input parameters
      sig do
        params(
          agent_assignment: T.untyped,
          repository: Repository,
          remote_ip: T.nilable(String),
          viewer: T.untyped,
          agent_id: T.nilable(Integer)
        ).returns(Issues::AgentAssignmentNewAttributes)
      end
      def get_copilot_attributes(agent_assignment, repository, remote_ip, viewer:, agent_id: nil)
        target_repository = agent_assignment&.target_repository || repository
        base_ref = agent_assignment&.base_ref || repository.default_branch
        custom_instructions = agent_assignment&.custom_instructions

        model = if FeatureFlag.vexi.enabled?(:coding_agent_model_selection, viewer, default: false)
          agent_assignment&.model
        end

        Issues::AgentAssignmentNewAttributes.new(
          target_repository: target_repository,
          base_ref: base_ref,
          custom_instructions: custom_instructions,
          custom_agent: agent_assignment&.custom_agent,
          remote_ip: remote_ip,
          model: model,
          agent_id: agent_id
        )
      end

      # Extracts the IDs for agentic-enabled bots from a collection of actors.
      def agentic_bot_ids_from(collection)
        return [] if collection.nil?

        collection.each_with_object([]) do |actor, ids|
          next unless actor.is_a?(Bot)
          ids << actor.id if AgenticApp.agent_for_bot_id(actor.id)
        end
      end

      # Extracts Copilot SWE bot IDs from a collection of actors.
      def copilot_bot_ids_from(collection)
        return [] if collection.nil?

        collection.each_with_object([]) do |actor, ids|
          next unless actor.is_a?(Bot)
          ids << actor.id if actor.slug == Apps::Privileged::CopilotSWEAgent::SLUG
        end
      end
    end
  end
end
