# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Rules
    class RestrictActionsEventsRule < BulkRunnableRule

      sig { void }
      def initialize
        super(rule_name: "restrict_action_events",
              display_name: "Restrict events",
              description: "Choose specific GitHub events that will trigger Actions workflows.",
              feature_flag: :actions_rulesets)
      end

      sig { override.params(source: T.nilable(Types::RuleSource)).returns(T::Boolean) }
      def is_user_configurable?(source = nil)
        true
      end

      sig { override.returns(T::Boolean) }
      def generate_api
        false
      end

      sig { override.returns(ParameterSchema::Object) }
      def parameter_schema
        schema = ParameterSchema::Object.root(ui_options: { hide_settings_container: true })
        schema.add_field(ParameterSchema::Array.new(name: "allowed_events", display_name: "Allowed events",
          content_type: :string, required: true, description: "Select the events that can trigger Actions workflows.",
          allowed_options: [
            { value: "push", display_name: "push", description: "The push event" },
            { value: "pull_request", display_name: "pull_request", description: "The pull request event" },
            { value: "deployment", display_name: "deployment", description: "The deployment event" },
            { value: "workflow_dispatch", display_name: "workflow_dispatch", description: "The workflow dispatch event" },
            { value: "schedule", display_name: "schedule", description: "The schedule event" },
          ], default_value: %w[push pull_request deployment workflow_dispatch schedule], ui_control: "enum_selector", apply_default_on_load: true))

        schema
      end

      sig do
        override.params(
          event: RuleEvent,
          rule_configs_by_action: T::Hash[RuleEvent::EventAction, T::Array[IRuleConfig]]
        )
        .returns(T::Array[RuleRun])
      end
      def run_evaluation(event, rule_configs_by_action)
        rule_configs_by_action.flat_map do |action, rule_configs|
          rule_configs.map { |rc| RuleRun.success(rule_config: rc, event_action: action) }
        end
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_source_types
        [:organization, :repository]
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_target_types
        [:actions]
      end
    end
  end
end
