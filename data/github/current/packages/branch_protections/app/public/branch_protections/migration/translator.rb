# typed: strict
# frozen_string_literal: true

module BranchProtections
  module Migration
    class Translator
      MIGRATORS = T.let([
        Rules::DeletionMigrator.new,
        Rules::ForcePushesMigrator.new,
        Rules::LockBranchMigrator.new,
        Rules::LinearHistoryMigrator.new,
      ].freeze, T::Array[Rules::BaseRuleMigrator])

      sig { params(protected_branch: ::ProtectedBranch).returns(T::Boolean) }
      def self.has_migrated_ruleset?(protected_branch)
        rulesets = protected_branch.repository&.rulesets
        return false unless rulesets

        name_prefix = "Migrated from #{protected_branch.name}"

        rulesets.map(&:name).any? { |name| name.start_with?(name_prefix) }
      end

      sig { params(protected_branch: ::ProtectedBranch).returns(T::Array[Structs::TranslationResult]) }
      def self.build_translations_for(protected_branch)
        MIGRATORS.filter_map { |migrator| migrator.translate(protected_branch) }
      end

      sig { params(protected_branch: ::ProtectedBranch).returns(T::Array[::RepositoryRuleset]) }
      def self.build_rulesets_for(protected_branch)
        translations = build_translations_for(protected_branch)

        group_by_bypass_actors(translations).map do |bypass_actors, rules|
          build_unpersisted_ruleset(
            protected_branch: protected_branch,
            translation_results: rules,
            bypass_actors: bypass_actors,
            name_suffix: translations.length > 1 ? "[#{rules.map(&:rule_type).join(", ")}]" : nil
          )
        end
      end

      sig { params(protected_branch: ::ProtectedBranch, rulesets: T.nilable(T::Array[RepositoryRuleset])).returns(T.untyped) }
      def self.coverage(protected_branch, rulesets: nil)
        return Structs::Coverage.new(status: Structs::CoverageStatus::Unknown) if protected_branch.name.include?("*")

        repo = T.must(protected_branch.repository)
        evaluator = BranchRuleEvaluator.for_repository_with_branch_name(repo, protected_branch.name)

        return Structs::Coverage.none if !evaluator || evaluator.rule_configs.nil?

        rule_configs = evaluator.rule_configs
        rulesets = evaluator.ref_rulesets unless rulesets.present?

        coverage_by_rule = (
          MIGRATORS.filter_map do |migrator|
            if migrator.is_enabled?(protected_branch)
              [
                migrator.rule_type,
                migrator.coverage(protected_branch, evaluator.rule_configs, rulesets)
              ]
            else
              nil
            end
          end
          # 1. group by rule type
          # 2. mutate the array to remove rule_type
          # 3. flatten the 2d array to a 1d array
          # 4. grab the first element since there will only be 1
        ).group_by(&:shift).transform_values { |c| T.cast(c.flatten.first, Structs::Coverage) }
        all_coverage = coverage_by_rule.values

        return Structs::Coverage.none if all_coverage.all?(&:none?)
        return Structs::Coverage.full if all_coverage.all?(&:full?)
        return Structs::Coverage.unknown if all_coverage.all?(&:unknown?)

        gaps = []
        gaps += all_coverage.filter(&:partial?).map { |c| c.gaps }.flatten
        gaps += all_coverage.filter(&:unknown?).map { |c| c.gaps }.flatten
        gaps += all_coverage.filter(&:none?).map { |c| c.gaps }.flatten

        Structs::Coverage.new(
          status: Structs::CoverageStatus::PartiallyCovered,
          gaps:,
        )
      end

      sig do
        params(results: T::Array[Structs::TranslationResult])
          .returns(T::Hash[T::Array[Structs::BypassActor], T::Array[Structs::TranslationResult]])
      end
      def self.group_by_bypass_actors(results)
        results.group_by(&:bypass_actors)
      end
      private_class_method :group_by_bypass_actors

      sig do
        params(
          protected_branch: ::ProtectedBranch,
          translation_results: T::Array[Structs::TranslationResult],
          bypass_actors: T::Array[Structs::BypassActor],
          enforcement: String,
          name_suffix: T.nilable(String),
        ).returns(::RepositoryRuleset)
      end
      def self.build_unpersisted_ruleset(protected_branch:, translation_results:, bypass_actors:, enforcement: "enabled", name_suffix: nil)
        ruleset = ::RepositoryRuleset.new(
          source: protected_branch.repository,
          name: "Migrated from #{protected_branch.name}#{name_suffix.present? ? " - #{name_suffix}" : ""}",
          target: "branch",
          enforcement:,
        )

        ruleset.conditions = [TargetingMapper.map(protected_branch.name)]

        translation_results.each do |result|
          ruleset.rule_configurations.build(
            rule_type: result.rule_type,
            parameters: result.parameters
          )
        end

        bypass_actors.each do |actor|
          ruleset.bypass_actors.build(
            actor_type: actor.actor_type,
            actor_id: actor.actor_id,
            bypass_mode: actor.bypass_mode
          )
        end

        ruleset
      end
      private_class_method :build_unpersisted_ruleset
    end
  end
end
