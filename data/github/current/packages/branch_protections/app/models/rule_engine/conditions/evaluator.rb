# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Conditions
    class Evaluator

      extend Timing

      TARGET_TYPES = T.let({
        "ref_name" => RefNameTarget.new,
        "repository_name" => RepositoryNameTarget.new,
        "repository_id" => RepositoryIdTarget.new,
        "repository_property" => RepositoryPropertiesTarget.new,
        "organization_name" => OrganizationNameTarget.new,
        "organization_id" => OrganizationIdTarget.new,
        "organization_property" => OrganizationPropertiesTarget.new,
      }, T::Hash[String, ConditionTarget])

      sig do
        params(
          targetables: T::Array[Targetable],
          parameters_by_condition: T::Hash[String, T::Hash[String, T.untyped]]
        ).returns(T::Array[Targetable])
      end
      def self.evaluate(targetables, parameters_by_condition)
        trace_time("condition_evaluation", span_attributes: {
          "gh.branch_protection_rule.condition_evaluator.target_count" => targetables.size,
          "gh.branch_protection_rule.generic_evaluator.condition_count" => parameters_by_condition.size
        }) do
          Targetable.recursive_prefill_parents(targetables)

          # Hash containing an evaluation set as an array and the targetables that it applies to
          # Automatically deduplicates keys based on the array contents
          # Array contents are [condition_target, relevant_attributes]
          evaluation_sets = T.let(Hash.new { |h, k| h[k] = [] },
            T::Hash[[String, T::Hash[Targetable::Attribute, T.untyped]], T::Array[Targetable]])
          targetables.each do |targetable|
            parameters_by_condition.keys.each do |condition|
              evaluator = TARGET_TYPES[condition]
              next unless evaluator

              needed_attributes = evaluator.targeted_attributes
              relevant_attributes = needed_attributes.to_h { |attribute| [attribute, targetable.get_attribute(attribute)] }

              T.must(evaluation_sets[[condition, relevant_attributes]]) << targetable
            end
          end

          failed_targetables = Set.new
          # Perform evaluations on each unit of the evaluation set and stores the result in each targetable's result set
          evaluation_sets.each do |(condition, target_attributes), set_targetables|
            evaluator = TARGET_TYPES[condition]
            parameters = T.must(parameters_by_condition[condition])

            trace_time("condition_evaluation", tags: ["target:#{condition}", "target_object:#{evaluator&.target_object&.serialize}"]) do
              unless evaluator&.run_condition(target_attributes, parameters)
                set_targetables.each { failed_targetables << _1 }
              end
            end
          end

          # Filter out targetables that do not satisfy all conditions
          targetables.reject { |targetable| failed_targetables.include?(targetable) }
        end
      end
    end
  end
end
