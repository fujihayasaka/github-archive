# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Rules
    class MaxRefUpdatesRule < RefUpdateRule
      sig { void }
      def initialize
        super(rule_name: "max_ref_updates", display_name: "Restrict push update count")
      end

      sig { override.returns(RuleEngine::ParameterSchema::Object) }
      def parameter_schema
        schema = ParameterSchema::Object.root
        schema.add_field(ParameterSchema::Field.new(name: "max_ref_updates", display_name: "Max ref updates",
          type: :integer, required: true, allowed_range: (2..1_000),
          description: "The maximum number of branches or tags that can be updated in a single push."))
        schema
      end

      sig { override.params(context: RuleEvaluationContext, rule_configs_by_ref_update: T::Hash[Git::Ref::Update, T::Array[RepositoryRuleConfiguration]]).returns(T::Array[RuleRun]) }
      def bulk_evaluate(context, rule_configs_by_ref_update)
        all_ref_updates = rule_configs_by_ref_update.keys

        rule_configs_by_ref_update.flat_map do |(ref_update, rule_configs)|
          rule_configs.map do |rule_config|
            max_ref_updates = rule_config.param("max_ref_updates").to_i

            if max_ref_updates > 0 && all_ref_updates.size > max_ref_updates
              RuleRun.failure(
                rule_config: rule_config,
                ref_update: ref_update,
                message: "Pushes can not update more than #{max_ref_updates} #{"branch".pluralize(max_ref_updates)} or #{"tag".pluralize(max_ref_updates)}."
              )
            else
              RuleRun.success(rule_config: rule_config, ref_update: ref_update)
            end
          end
        end
      end
    end
  end
end
