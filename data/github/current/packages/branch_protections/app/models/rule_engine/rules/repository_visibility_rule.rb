# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Rules
    class RepositoryVisibilityRule < RepositoryOperationRule
      sig { void }
      def initialize
        super(rule_name: "repository_visibility",
              display_name: "Restrict visibility",
              description: "New repositories and visibility changes are limited to specified visibilities, unless the actor is on the allow list.",
              operation_keys: [:change_visibility],
              feature_flag: :member_privilege_rulesets)
      end

      sig { override.returns(RuleEngine::ParameterSchema::Object) }
      def parameter_schema
        schema = ParameterSchema::Object.root
        schema.add_field(ParameterSchema::Field.new(name: "public", display_name: "Public", type: :boolean,
          description: "Anyone on the internet can see this repository. You choose who can commit.", default_value: false))
        schema.add_field(ParameterSchema::Field.new(name: "internal", display_name: "Internal", type: :boolean,
          description: "Enterprise members can see this repository. You choose who can commit.", default_value: false))
        schema.add_field(ParameterSchema::Field.new(name: "private", display_name: "Private", type: :boolean,
          description: "You choose who can see and commit to this repository.", default_value: false))
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
            # this rule_config has three parameters (public, internal, and private)
            # if the parameter is true it means that visibility is allowed, if it's false it means it's restricted
            # action.operation_value is the visibility a user wants to change the repo to (public, private, internal)
            success = rule_config.parameters["#{action.operation_value}"]
            if success
              RuleRun.success(event_action: action, rule_config:)
            else
              RuleRun.failure(event_action: action, rule_config:, message: "Repository visibility can not be set to #{action.operation_value}")
            end
          end
        end.compact
      end

      module StatusMethods
        extend T::Helpers

        requires_ancestor { RepositoryRuleState }

        sig { params(actor: T.nilable(User)).returns(T::Array[Symbol]) }
        def allowed_visibilities(actor)
          allowed_visibilities = [:public, :internal, :private]
          enforced_rules_by_type("repository_visibility", actor).each do |config|
            if config.parameters["public"] == false
              allowed_visibilities.delete(:public)
            end
            if config.parameters["internal"] == false
              allowed_visibilities.delete(:internal)
            end
            if config.parameters["private"] == false
              allowed_visibilities.delete(:private)
            end
          end

          allowed_visibilities
        end
      end
    end
  end
end
