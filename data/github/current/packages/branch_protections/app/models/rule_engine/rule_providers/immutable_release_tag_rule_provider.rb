# typed: true
# frozen_string_literal: true

module RuleEngine
  module RuleProviders
    class ImmutableReleaseTagRuleProvider < RuleProvider
      include GitRuleProvider

      def initialize
        super(identifier: "immutable_release_tag")
      end

      sig do
        override.params(
          repository: Repository,
          ref_updates: T::Array[Git::Ref::Update],
          actor: T.nilable(Types::Actor)
        ).returns(T::Array[IRuleConfig])
      end
      def rules_for_ref_updates(repository, ref_updates, actor)
        # Filter ref updates to only include those that are tag updates
        tag_updates = ref_updates.select(&:tag?)
        return [] if tag_updates.empty?

        # Extract tag names from the updates
        tag_names = tag_updates.map(&:unqualified_refname)

        # Filter tag names against the repository's immutable release tags
        tags = ::Releases::Public.immutable_release_tags(repository, tag_names)
        return [] if tags.empty?

        # Collect list of refs to protect from creates/updates
        protected_update_refs = tags.map do |tag_info|
          "refs/tags/#{tag_info.tag_name}"
        end

        # Collect list of refs to protect from deletions (refs associated with now-deleted releases CAN be deleted)
        protected_deletion_refs = tags.filter_map do |tag_info|
          tag_info.release_status == :deleted ? nil : "refs/tags/#{tag_info.tag_name}"
        end

        [
          RuntimeRuleConfig.new(
            provider: self,
            source: repository,
            rule_type: "creation",
            matching_ref_names: protected_update_refs
          ),
          RuntimeRuleConfig.new(
            provider: self,
            source: repository,
            rule_type: "update",
            matching_ref_names: protected_update_refs
          ),
          RuntimeRuleConfig.new(
            provider: self,
            source: repository,
            rule_type: "deletion",
            matching_ref_names: protected_deletion_refs
          )
        ]
      end

      sig do
        override.params(
          repository: Repository,
          ref_names: T::Array[String]
        ).returns(T::Array[IRuleConfig])
      end
      def rule_for_branch_evaluators(repository, ref_names)
        []
      end

      # Rules for immutable release tags do not allow bypassing
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
