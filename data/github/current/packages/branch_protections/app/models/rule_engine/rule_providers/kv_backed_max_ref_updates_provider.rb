# typed: true
# frozen_string_literal: true

module RuleEngine
  module RuleProviders
    class KvBackedMaxRefUpdatesProvider < RuleProvider
      include GitRuleProvider

      def initialize
        super(identifier: "kv_backed_max_ref_updates")
      end

      sig { override.params(repository: Repository, ref_updates: T::Array[Git::Ref::Update], actor: T.nilable(Types::Actor)).returns(T::Array[RepositoryRuleConfiguration]) }
      def rules_for_ref_updates(repository, ref_updates, actor)
        return [] unless repository.supports_protected_branches?
        create_rules(repository, ref_updates.map(&:refname))
      end

      sig { override.params(repository: Repository, ref_names: T::Array[String]).returns(T::Array[RepositoryRuleConfiguration]) }
      def rule_for_branch_evaluators(repository, ref_names)
        # Not relevant for BranchRuleEvaluator
        []
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

      private

      def create_rules(repository, matching_refs)
        return [] unless matching_refs.length > 1
        return [] unless repository.max_ref_updates > 0

        [RepositoryRuleConfiguration.create_provider_rule(
          provider: self,
          source: repository,
          rule_type: "max_ref_updates",
          matching_ref_names: matching_refs,
          parameters: {
            "max_ref_updates" => repository.max_ref_updates
          }
        )]
      end
    end
  end
end
