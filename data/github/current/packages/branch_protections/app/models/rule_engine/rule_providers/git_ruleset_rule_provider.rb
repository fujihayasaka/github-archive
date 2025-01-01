# typed: strict
# frozen_string_literal: true

module RuleEngine
  module RuleProviders
    class GitRulesetRuleProvider < RulesetRuleProvider
      include GitRuleProvider

      abstract!

      RULESET_PROVIDERS = T.let([
        "ref_ruleset",
        "push_ruleset",
        "repository_ruleset" # legacy
      ].freeze, T::Array[String])

      include Bypasses

      sig { params(identifier: String).void }
      def initialize(identifier:)
        super(identifier:)
      end

      sig { abstract.params(repository: Repository).returns(T::Array[RepositoryRuleset]) }
      def load_rulesets(repository); end

      # GitRuleProvider overrides `rules_for_event` so this method is unused
      sig { override.params(event: RepositoryEvent).returns(T::Array[RepositoryRuleset]) }
      def load_rulesets_for_event(event)
        []
      end

      sig do
        override.params(
          repository: Repository,
          ref_updates: T::Array[Git::Ref::Update],
          actor: T.nilable(Types::Actor)
        ).returns(T::Array[RepositoryRuleConfiguration])
      end
      def rules_for_ref_updates(repository, ref_updates, actor)
        return [] unless repository.supports_protected_branches?

        rulesets = load_rulesets(repository)

        # Preload history because this gets used on the produced RuleRuns
        GitHub::PrefillAssociations.prefill_batch_method(rulesets, :latest_history_id)

        rulesets.flat_map do |ruleset|
          configs = ruleset.rule_configurations.to_ary
          supported_rules = ruleset.available_rule_types
          matching_ref_names = ruleset.bulk_filter_targetable(ref_updates).map { _1.get_attribute(RuleEngine::Conditions::Targetable::Attribute::RefName) }.uniq
          next [] if matching_ref_names.empty?

          configs.filter_map do |config|
            next unless supported_rules.include?(config.rule_type)
            config.matching_ref_names = matching_ref_names
            config.provider = self
            config
          end
        end
      end

      sig { override.params(repository: Repository, ref_names: T::Array[String]).returns(T::Array[RepositoryRuleConfiguration]) }
      def rule_for_branch_evaluators(repository, ref_names)
        rulesets = load_rulesets(repository)
        targetables = ref_names.map { |ref_name| Conditions::Targets::Ref.new(repository:, ref_name:) }

        rulesets.flat_map do |ruleset|
          matching_ref_names = ruleset.bulk_filter_targetable(targetables).map { _1.get_attribute(RuleEngine::Conditions::Targetable::Attribute::RefName) }.uniq
          next [] if matching_ref_names.empty?
          ruleset.rule_configurations.each do |config|
            config.matching_ref_names = matching_ref_names
            config.provider = self
          end
        end
      end
    end
  end
end
