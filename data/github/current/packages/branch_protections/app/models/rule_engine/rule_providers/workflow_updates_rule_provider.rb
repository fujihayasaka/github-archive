# typed: true
# frozen_string_literal: true

module RuleEngine
  module RuleProviders
    class WorkflowUpdatesRuleProvider < RuleProvider
      include GitRuleProvider

      def initialize
        super(identifier: "workflow_updates")
      end

      sig { override.params(repository: Repository, ref_updates: T::Array[Git::Ref::Update], actor: T.nilable(Types::Actor)).returns(T::Array[IRuleConfig]) }
      def rules_for_ref_updates(repository, ref_updates, actor)
        return [] unless RefUpdates::WorkflowUpdatesPolicy.new(actor, repository).workflow_scope_missing?

        [RuntimeRuleConfig.new(
          provider: self,
          source: repository,
          rule_type: "workflow_updates",
          matching_ref_names: ref_updates.map { |ref_update| ref_update.get_attribute(Targeting::Attribute::RefName) },
        )]
      end

      sig { override.params(repository: Repository, ref_names: T::Array[String]).returns(T::Array[IRuleConfig]) }
      def rule_for_branch_evaluators(repository, ref_names)
        []
      end

      sig do
        override.params(
          rule_config: IRuleConfig,
          actor: T.nilable(Types::Actor),
          targetable: Targeting::Targetable,
          rule_run: T.nilable(RuleRun)
        ).returns(T::Boolean)
      end
      def can_bypass?(rule_config, actor, targetable, rule_run = nil)
        false
      end
    end
  end
end
