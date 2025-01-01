# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Rules
    class RepositoryNameRestrictionRule < RepositoryOperationRule
      include GitHub::Memoizer

      sig { void }
      def initialize
        super(rule_name: "repository_name",
              display_name: "Restrict names",
              description: "New repository names and name changes are limited to the specific patterns, unless the actor is on the allow list.",
              operation_keys: [:create, :rename],
              feature_flag: :member_privilege_rulesets,
        )
      end

      sig { override.returns(RuleEngine::ParameterSchema::Object) }
      def parameter_schema
        schema = ParameterSchema::Object.root
        schema.add_field(ParameterSchema::Field.new(
          name: "negate",
          display_name: "Condition",
          type: :boolean,
          description: "If true, the rule will fail if the pattern matches.",
          default_value: false,
          ui_control: "negate_condition",
          ))
        schema.add_field(ParameterSchema::Field.new(
          name: "pattern",
          display_name: "Naming pattern",
          type: :string,
          required: true,
          description: "Define the naming pattern using a regular expression.",
          validator: method(:ensure_valid_pattern),
          ui_control: "regex_pattern",
        ))
        schema
      end

      sig do
        override.params(
          event: RuleEngine::Events::RepositoryOperationEvent,
          rule_configs_by_action: T::Hash[EventActionRepositoryOperation, T::Array[RepositoryRuleConfiguration]]
        )
        .returns(T::Array[RuleEngine::RuleRun])
      end
      def evaluate_operations(event, rule_configs_by_action)
        rule_configs_by_action.flat_map do |action, rule_configs|
          rule_configs.map do |rule_config|
            matches = matches_regex?(event.repository_model.name, rule_config.parameters["pattern"])
            negate = normalize_negate_param(rule_config)
            success = negate ? !matches : matches

            if success
              RuleRun.success(event_action: action, rule_config:)
            else
              RuleRun.failure(event_action: action, rule_config:, message: "Repository name #{negate ? "must not" : "must"} match \"#{rule_config.parameters["pattern"]}\"")
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

      module StatusMethods
        extend T::Helpers

        requires_ancestor { RepositoryRuleState }

        sig { params(name: String).returns(T::Boolean) }
        def name_allowed?(name)
          configs_by_type("repository_name").each do |config|
            negate = config.has_param("negate") ? ActiveModel::Type::Boolean.new.cast(config.param("negate")) : false
            if negate
              return false if regex_validator.matches?(name, config.parameters["pattern"])
            else
              return false unless regex_validator.matches?(name, config.parameters["pattern"])
            end
          end

          true
        end
      end
    end
  end
end
