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
        # Tag protections are fully deprecated and disabled
        []
      end

      sig { override.params(repository: Repository, ref_names: T::Array[String]).returns(T::Array[RepositoryRuleConfiguration]) }
      def rule_for_branch_evaluators(repository, ref_names)
        # Tag protections are fully deprecated and disabled
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
