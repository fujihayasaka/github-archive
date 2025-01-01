# typed: strict
# frozen_string_literal: true

module RuleEngine
  # Abstract base class for metadata pattern rules
  class MetadataPatternRule < CommitRule
    abstract!

    sig { params(rule_name: String, display_name: String, feature_flag: T.nilable(Symbol)).void }
    def initialize(rule_name:, display_name:, feature_flag: nil)
      super(rule_name:, display_name:, feature_flag:)
    end

    sig { params(source: T.nilable(RuleEngine::Types::RuleSource)).returns(T::Boolean) }
    def is_user_configurable?(source = nil)
      true
    end

    sig { abstract.returns(String) }
    def property_name; end

    sig { abstract.returns(String) }
    def property_description; end

    sig { abstract.params(candidate: MetadataSources::Types::Candidate).returns(T.nilable(String)) }
    def property_value(candidate); end

    sig { overridable.returns(T::Array[{ type: String, display_name: String }]) }
    def supported_operators
      [{
        "type": "starts_with",
        "display_name": "start with a matching pattern"
      }, {
        "type": "ends_with",
        "display_name": "end with a matching pattern"
      }, {
        "type": "contains",
        "display_name": "contain a matching pattern"
      }, {
        "type": "regex",
        "display_name": "match a given regex pattern"
      }].freeze
    end

    sig { override.returns(RuleEngine::ParameterSchema::Object) }
    def parameter_schema
      schema = ParameterSchema::Object.root
      schema.add_field(ParameterSchema::Field.new(name: "operator", display_name: "Operator", type: :string, required: true,
        description: "The operator to use for matching.",
        allowed_values: supported_operators.map { |operator| operator[:type] }))
      schema.add_field(ParameterSchema::Field.new(name: "pattern", display_name: "Pattern", type: :string, required: true,
        description: "The pattern to match with.", validator: method(:ensure_valid_pattern)))
      schema.add_field(ParameterSchema::Field.new(name: "negate", display_name: "Negate", type: :boolean,
        description: "If true, the rule will fail if the pattern matches.", default_value: false))
      schema.add_field(ParameterSchema::Field.new(name: "name", display_name: "Name", type: :string,
        description: "How this rule will appear to users.", default_value: ""))
      schema
    end

    sig { override.returns(Symbol) }
    def supported_plan
      :enterprise_rulesets
    end

    sig do
      override.params(
        context: RuleEvaluationContext,
        ref_update: Git::Ref::Update,
        rule_config: RepositoryRuleConfiguration,
        candidate: MetadataSources::Types::Candidate,
      ).returns(EvaluationResult)
    end
    def evaluate_candidate(context, ref_update, rule_config, candidate)
      return EvaluationResult.success(candidate:) if ref_update.deletion?

      value = property_value(candidate)
      pattern = rule_config.param("pattern")
      negate = normalize_negate_param(rule_config)
      regex = nil

      case rule_config.param("operator")
      when "starts_with"
        regex = "^#{Regexp.escape(pattern)}"
      when "ends_with"
        regex = "#{Regexp.escape(pattern)}$"
      when "contains"
        regex = ".*#{Regexp.escape(pattern)}.*"
      else
        regex = pattern
      end

      return EvaluationResult.success(candidate:) if regex.nil?
      return EvaluationResult.failure(candidate:) if value.nil?

      result = context.matches_regex?(value, regex)
      success = negate ? !result : result
      EvaluationResult.new(candidate: candidate, success: success)
    end

    sig do
      override.params(
        context: RuleEvaluationContext,
        ref_update: Git::Ref::Update,
        rule_config: RepositoryRuleConfiguration,
        violations: T::Array[Violation],
      )
      .returns(RuleRun)
    end
    def generate_evaluation_result(context, ref_update, rule_config, violations)
      return RuleRun.success(rule_config: rule_config, ref_update: ref_update) if violations.empty?

      operator = rule_config.param("operator")
      pattern = rule_config.param("pattern")
      negate = normalize_negate_param(rule_config)

      supported_operator = T.must(supported_operators.find { |o| o[:type] == operator } || supported_operators.last)
      prefix = negate ? "must not" : "must"

      message = "#{property_description} #{prefix} #{supported_operator[:display_name]}: #{pattern}"

      RuleRun.failure(
        rule_config: rule_config,
        ref_update: ref_update,
        message: message,
        violations: violations.filter_map do |violation|
          case violation.candidate
          when MetadataSources::Types::CommitCandidate
            commit_candidate = T.cast(violation.candidate, MetadataSources::Types::CommitCandidate)
            { candidate: T.must(commit_candidate.oid) } if commit_candidate.oid
          else
            nil
          end
        end
    )
    end

    private

    sig { params(rule_config: RepositoryRuleConfiguration).returns(T::Boolean) }
    def normalize_negate_param(rule_config)
      rule_config.has_param("negate") ? ActiveModel::Type::Boolean.new.cast(rule_config.param("negate")) : false
    end

    sig { params(context: RuleEngine::ParameterSchema::ValidationContext, pattern: String, errors: T::Array[T.untyped]).void }
    def ensure_valid_pattern(context, pattern, errors)
      return unless context.parent["operator"] == "regex"

      unless Regex::RE2Helper.new.is_valid?(pattern)
        errors << {
          error_code: :invalid_pattern,
          message: "Invalid pattern: `#{pattern}`",
          value: pattern
        }
      end
    end
  end
end
