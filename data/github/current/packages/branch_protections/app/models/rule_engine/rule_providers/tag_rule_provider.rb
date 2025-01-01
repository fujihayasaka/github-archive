# typed: true
# frozen_string_literal: true

module RuleEngine
  module RuleProviders
    class TagRuleProvider < RuleProvider
      include GitRuleProvider

      def initialize
        super(identifier: "tag_permission")
      end

      sig { override.params(repository: Repository, ref_updates: T::Array[Git::Ref::Update], actor: T.nilable(Types::Actor)).returns(T::Array[RepositoryRuleConfiguration]) }
      def rules_for_ref_updates(repository, ref_updates, actor)
        return [] unless repository.supports_protected_branches?
        return [] unless ref_updates.any?(&:tag?)

        matching_ref_names = ref_updates
          .select { |ru| ru.tag? && repository.tag_protected?(ru.refname.delete_prefix("refs/tags/")) }
          .map(&:refname)

        if matching_ref_names.any?
          [create_rule(repository, matching_ref_names)]
        else
          []
        end
      end

      sig { override.params(repository: Repository, ref_names: T::Array[String]).returns(T::Array[RepositoryRuleConfiguration]) }
      def rule_for_branch_evaluators(repository, ref_names)
        matching_ref_names = ref_names
          .select { |ref| ref.start_with?("refs/tags/") && repository.tag_protected?(ref.delete_prefix("refs/tags/")) }

        if matching_ref_names.any?
          [create_rule(repository, matching_ref_names)]
        else
          []
        end
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

      def create_rule(repository, matching_refs)
        RepositoryRuleConfiguration.create_provider_rule(
          provider: self,
          source: repository,
          rule_type: "tag",
          matching_ref_names: matching_refs
        )
      end
    end
  end
end
