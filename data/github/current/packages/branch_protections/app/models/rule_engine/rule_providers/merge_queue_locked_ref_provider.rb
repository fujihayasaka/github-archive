# typed: true
# frozen_string_literal: true

module RuleEngine
  module RuleProviders
    class MergeQueueLockedRefProvider < RuleProvider
      include GitRuleProvider

      def initialize
        super(identifier: "merge_queue_locked_ref")
      end

      sig { override.params(repository: Repository, ref_updates: T::Array[Git::Ref::Update], actor: T.nilable(Types::Actor)).returns(T::Array[RepositoryRuleConfiguration]) }
      def rules_for_ref_updates(repository, ref_updates, actor)
        return [] unless repository.supports_protected_branches?
        return [] unless repository.merge_queue_enabled?

        branch_names = ref_updates.filter(&:branch?).map(&:branch_name)
        return [] unless branch_names.any?

        refs_in_queue = Set.new(MergeQueueLockedRef.where(
          repository: repository,
          ref: branch_names,
        ).pluck(:ref))

        return [] unless refs_in_queue.any?

        [RepositoryRuleConfiguration.create_provider_rule(
          provider: self,
          source: repository,
          rule_type: "merge_queue_locked_ref",
          matching_ref_names: refs_in_queue.map { |ref| "refs/heads/#{ref}" }
        )]
      end

      sig { override.params(repository: Repository, ref_names: T::Array[String]).returns(T::Array[RepositoryRuleConfiguration]) }
      def rule_for_branch_evaluators(repository, ref_names)
        # The merge queue locked ref rule is not relevant for the BranchRuleEvaluator
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
