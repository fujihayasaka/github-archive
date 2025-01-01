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

        configs_by_ref_update = Hash.new { |h, k| h[k] = [] }

        rulesets.flat_map do |ruleset|
          configs = ruleset.rule_configurations.to_ary
          configs.each do |config|
            config.matching_ref_names = []
            config.provider = self
          end

          ref_updates.each do |ref_update|
            next unless ruleset.should_evaluate?(Conditions::RulesetTargetContext.new(repository:, ref_update:))
            supported_rules = ruleset.available_rule_types
            configs.each do |rule|
              next unless supported_rules.include?(rule.rule_type)

              rule.matching_ref_names << ref_update.refname
            end
          end

          configs.select { |config| config.matching_ref_names.any? }
        end
      end

      sig { override.params(repository: Repository, ref_names: T::Array[String]).returns(T::Array[RepositoryRuleConfiguration]) }
      def rule_for_branch_evaluators(repository, ref_names)
        rulesets = load_rulesets(repository)
        ref_names.flat_map do |ref_name|
          context = RuleEngine::Conditions::RulesetTargetContext.new(repository:, ref_name:)
          configs = rulesets.filter { |ruleset| ruleset.should_evaluate?(context) }.map(&:rule_configurations).flatten
          configs.each do |config|
            config.matching_ref_names = Array(config.matching_ref_names) << ref_name
            config.provider = self
          end
          configs
        end
      end
    end
  end
end
