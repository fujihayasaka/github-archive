# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Rules
    class RepositoryNameRestrictionRule < RepositoryOperationRule
      include GitHub::Memoizer

      sig { void }
      def initialize
        super(rule_name: "restrict_repository_name",
              display_name: "Restrict repository name",
              description: "New repository names and name changes are limited to the specific patterns, unless the actor is on the Allowed list.",
              operation_keys: [:create, :rename],
              feature_flag: :member_privilege_rulesets,
        )
      end

      sig { override.returns(RuleEngine::ParameterSchema::Object) }
      def parameter_schema
        schema = ParameterSchema::Object.root
        schema.add_field(ParameterSchema::Field.new(name: "pattern", display_name: "Pattern", type: :string, required: true,
          description: "The regex pattern to match with.", validator: method(:ensure_valid_pattern)))
        schema.add_field(ParameterSchema::Field.new(name: "negate", display_name: "Negate", type: :boolean,
          description: "If true, the rule will fail if the pattern matches.", default_value: false))
        schema
      end

      sig do
        override.params(
          event: RuleEngine::RuleEvent,
          rule_configs_by_action: T::Hash[RuleEvent::EventAction, T::Array[RepositoryRuleConfiguration]]
        )
        .returns(T::Array[RuleEngine::RuleRun])
      end
      def run_evaluation(event, rule_configs_by_action)
        rule_configs_by_action.flat_map do |action, rule_configs|
          next unless action.is_a?(Events::RepositoryOperationEvent::Operation)
          next unless event.is_a?(RuleEngine::Events::RepositoryOperationEvent)
          next unless operation_keys.include?(action.operation_key)

          rule_configs.map do |rule_config|
            next unless rule_config.rule_type == rule_name
            matches = matches_regex?(T.must(event.repository.name), rule_config.parameters["pattern"])
            negate = normalize_negate_param(rule_config)
            success = negate ? !matches : matches

            if success
              RuleRun.success(event_action: action, rule_config:)
            else
              RuleRun.failure(event_action: action, rule_config:, message: "Repository name doesn't match ruleset restriction")
            end
          end
        end.compact
      end

      private

      sig { params(rule_config: RepositoryRuleConfiguration).returns(T::Boolean) }
      def normalize_negate_param(rule_config)
        rule_config.has_param("negate") ? ActiveModel::Type::Boolean.new.cast(rule_config.param("negate")) : false
      end

      sig { params(value: String, regex: String).returns(T::Boolean) }
      def matches_regex?(value, regex)
        regex_validator.matches?(value, regex)
      end

      sig { params(context: RuleEngine::ParameterSchema::ValidationContext, pattern: String, errors: T::Array[T.untyped]).void }
      def ensure_valid_pattern(context, pattern, errors)
        return unless context.parent["operator"] == "regex"

        unless regex_validator.is_valid?(pattern)
          errors << {
            error_code: :invalid_pattern,
            message: "Invalid pattern: `#{pattern}`",
            value: pattern
          }
        end
      end

      sig { returns(Regex::RE2Helper) }
      memoize def regex_validator
        Regex::RE2Helper.new
      end
    end
  end
end
