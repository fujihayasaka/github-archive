# typed: true
# frozen_string_literal: true

module RuleEngine
  module RuleProviders
    class RequiredWorkflowRuleProvider < RuleProvider
      include GitRuleProvider

      def initialize
        super(identifier: "required_workflow")
      end

      sig { override.params(repository: Repository, ref_updates: T::Array[Git::Ref::Update], actor: T.nilable(Types::Actor)).returns(T::Array[RepositoryRuleConfiguration]) }
      def rules_for_ref_updates(repository, ref_updates, actor)
        [] # deprecated
      end

      sig { override.params(repository: Repository, ref_names: T::Array[String]).returns(T::Array[RepositoryRuleConfiguration]) }
      def rule_for_branch_evaluators(repository, ref_names)
        [] # deprecated
      end

      sig do
        override.params(
          rule_config: RepositoryRuleConfiguration,
          actor: T.nilable(Types::Actor),
          repository: T.nilable(Repository),
          rule_run: T.nilable(RuleRun)
        ).returns(T::Boolean)
      end
      def can_bypass?(rule_config, actor, repository, rule_run = nil)
        false
      end

      sig { override.params(rule_run: RuleRun).returns(T.nilable(String)) }
      def insights_category(rule_run)
        "Classic required workflows"
      end
    end
  end
end
