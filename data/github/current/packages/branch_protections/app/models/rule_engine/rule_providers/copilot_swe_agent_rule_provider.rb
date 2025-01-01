# typed: true
# frozen_string_literal: true

module RuleEngine
  module RuleProviders
    class CopilotSweAgentRuleProvider < RuleProvider
      include GitRuleProvider

      COPILOT_BRANCH_PREFIX = "refs/heads/copilot/".freeze

      def initialize
        super(identifier: "copilot_swe_agent")
      end

      sig { override.params(repository: Repository, ref_updates: T::Array[Git::Ref::Update], actor: T.nilable(Types::Actor)).returns(T::Array[RepositoryRuleConfiguration]) }
      def rules_for_ref_updates(repository, ref_updates, actor)
        # Copilot is not available on GitHub Enterprise
        return [] if GitHub.enterprise?
        # Passing nil for the user parameter since the actor here is a bot
        # And the copilot_swe_agent_enabled? method only needs user for policy/model checks
        return [] unless actor.is_a?(Bot) && repository.copilot_swe_agent_enabled?(actor)
        return [] unless actor.is_a?(Bot) && actor == Apps::Privileged.integration(:copilot_swe_agent)&.bot

        disallowed_refs = ref_updates.map(&:refname).reject { |ref| ref.starts_with?(COPILOT_BRANCH_PREFIX) }

        [RepositoryRuleConfiguration.create_provider_rule(
          provider: self,
          source: repository,
          rule_type: "creation",
          matching_ref_names: disallowed_refs
        ), RepositoryRuleConfiguration.create_provider_rule(
          provider: self,
          source: repository,
          rule_type: "update",
          matching_ref_names: disallowed_refs
        ), RepositoryRuleConfiguration.create_provider_rule(
          provider: self,
          source: repository,
          rule_type: "deletion",
          matching_ref_names: disallowed_refs
        )]
      end

      sig { override.params(repository: Repository, ref_names: T::Array[String]).returns(T::Array[RepositoryRuleConfiguration]) }
      def rule_for_branch_evaluators(repository, ref_names)
        []
      end

      sig do
        override.params(
          rule_config: RepositoryRuleConfiguration,
          actor: T.nilable(Types::Actor),
          targetable: RuleEngine::Conditions::Targetable,
          rule_run: T.nilable(RuleRun)
        ).returns(T::Boolean)
      end
      def can_bypass?(rule_config, actor, targetable, rule_run = nil)
        false
      end
    end
  end
end
