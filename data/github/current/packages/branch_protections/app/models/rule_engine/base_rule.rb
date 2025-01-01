# typed: true
# frozen_string_literal: true

module RuleEngine

  # Abstract base class for all rule implementations
  class BaseRule
    extend T::Helpers

    include Scientist
    include Validations
    abstract!

    sig { params(rule_name: String, display_name: String, description: T.nilable(String), feature_flag: T.nilable(Symbol), beta: T::Boolean, beta_api_note: T::Boolean).void }
    def initialize(rule_name:, display_name:, description: nil, feature_flag: nil, beta: false, beta_api_note: false)
      @rule_name = rule_name
      @display_name = display_name
      @description = description
      @feature_flag = feature_flag
      @beta = beta
      @beta_api_note = beta_api_note # When true, add a note to the API that this rule is in beta and subject to change
    end

    sig { returns(String) }
    attr_reader :rule_name

    sig { returns(String) }
    attr_reader :display_name

    sig { returns(T.nilable(String)) }
    attr_reader :description

    sig { returns(T.nilable(Symbol)) }
    attr_reader :feature_flag

    sig { returns(T::Boolean) }
    attr_reader :beta

    sig { returns(T::Boolean) }
    attr_reader :beta_api_note

    sig { params(source: T.nilable(RuleEngine::Types::RuleSource)).returns(T::Boolean) }
    def is_user_configurable?(source = nil)
      false
    end

    sig { params(source: T.nilable(FeatureFlag::IFeatureTarget)).returns(T::Boolean) }
    def is_feature_enabled?(source)
      return true if (feature = feature_flag).nil?
      return false if source.nil?

      if source.is_a?(RuleSettingsDependency)
        source.feature_enabled_for_source?(feature)
      else
        source.feature_enabled?(feature)
      end
    end

    sig { params(source: RuleEngine::Types::RuleSource).returns(T::Boolean) }
    def is_supported_by_source_type?(source)
      supported_source_types.include?(source.class.name&.downcase&.to_sym)
    end

    def is_supported_by_plan?(source, allow_upsell: false)
      source.plan_supports?(supported_plan) ||
        (allow_upsell && supported_plan == :protected_branches) ||
        (allow_upsell && supported_plan == :enterprise_rulesets && (source.is_a?(Organization) || source.in_organization?))
    end

    def is_supported_by_target?(target)
      supported_target_types.include?(target&.to_sym)
    end

    # Allows rules to provide the UI (Insights) with additional metadata based on a rule run
    sig { overridable.params(rule_run: RuleRun).returns(T.nilable(Hash)) }
    def insights_ui_metadata(rule_run)
      nil
    end

    # Allows rules to provide the UI (view / edit ruleset) with additional metadata based on the rule config
    sig { overridable.params(rule_config: RepositoryRuleConfiguration).returns(T.nilable(Hash)) }
    def ruleset_ui_metadata(rule_config)
      nil
    end

    # Indicates whether a rule should be skipped from being evaluated
    # Rules can implement this method to exclude themselves from evaluation at runtime based on context parameters
    sig { overridable.params(context: RuleEvaluationContext, rule_config: RepositoryRuleConfiguration).returns(T::Boolean) }
    def skip_evaluation?(context, rule_config)
      false
    end

    # Indicates whether a rule should be skipped from being evaluated
    # Rules can implement this method to exclude themselves from evaluation at runtime based on context parameters
    sig { overridable.params(event: RuleEvent, rule_config: RepositoryRuleConfiguration).returns(T::Boolean) }
    def skip_evaluation_event?(event, rule_config)
      return false unless event.is_a?(GitEvent)
      skip_evaluation?(event.legacy_evaluation_context, rule_config)
    end

    # Indicates the minimum GHES version in which this rule was first introduced.
    # This needs to be set for all rules that are user configurable and not feature-flagged
    # so the dump-rules-schema script can generate the correct documentation for all GHES versions.
    sig { overridable.returns(T.nilable(String)) }
    def minimum_ghes_version
      nil
    end

    # By default, false when a feature flag is present
    # - REST API docs are not published but REST API requests can be made on repos where the feature flag is enabled
    # - GraphQL requests require passing the feature flag in the request header
    #
    # Keep in mind that there is no official beta for the APIs.
    # Once published, we have to be cautious about changes as they may break integrators
    #
    # If this method is overridden, keep in mind you can can delete the overriding method once the feature flag is removed
    sig { overridable.returns(T::Boolean) }
    def publish_api
      is_user_configurable? && feature_flag.nil?
    end

    protected

    sig { overridable.returns(Symbol) }
    def supported_plan
      :protected_branches
    end

    sig { overridable.returns(T::Array[Symbol]) }
    def supported_source_types
      [:repository, :organization, :business]
    end

    sig { overridable.returns(T::Array[Symbol]) }
    def supported_target_types
      [:branch, :tag]
    end
  end
end
