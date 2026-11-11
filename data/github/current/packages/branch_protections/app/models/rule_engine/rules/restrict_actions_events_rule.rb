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

      # Events excluded from the picker. Workflow runs carrying one of these still
      # reach `evaluate_workflow_run`, which short-circuits to success; the actors
      # rule remains in charge of gating them.
      EXCLUDED_EVENTS = T.let(Set.new(%w{dynamic}).freeze, T::Set[String])

      ALLOWED_EVENTS = T.let((Repository::WorkflowsDependency::ALL_EVENTS - EXCLUDED_EVENTS).freeze, T::Set[String])
      # Sorted array for deterministic iteration order across Ruby versions
      ALLOWED_EVENTS_LIST = T.let(ALLOWED_EVENTS.to_a.sort.freeze, T::Array[String])
      DEFAULT_ALLOWED_EVENTS = T.let(ALLOWED_EVENTS_LIST.dup.freeze, T::Array[String])
      DANGEROUS_EVENT_WARNINGS = T.let({
        "pull_request_target" => {
          description: "Caution: This event runs with write permissions and access to secrets, even when triggered from a fork. Use with care.",
          docs_url_id: "actions/events-pull-request-target",
        },
      }.freeze, T::Hash[String, { description: String, docs_url_id: String }])

      sig { override.returns(ParameterSchema::Object) }
      def parameter_schema
        schema = ParameterSchema::Object.root(ui_options: { hide_settings_container: true })
        schema.add_field(ParameterSchema::Array.new(name: "allowed_events", display_name: "Allowed events",
          content_type: :string, required: true, description: "Select the events that can trigger Actions workflows.",
          allowed_options: ALLOWED_EVENTS_LIST.map do |event|
            danger_info = DANGEROUS_EVENT_WARNINGS[event]
            {
              value: event,
              display_name: event,
              description: nil,
              warning: danger_info ? danger_info[:description] : nil,
              pinned: danger_info.present?,
              docs_url: danger_info ? DocsUrlConfig.url_for(danger_info[:docs_url_id]) : nil,
            }
          end,
          default_value: DEFAULT_ALLOWED_EVENTS, ui_control: "enum_selector", apply_default_on_load: true))

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
          rule_configs.map do |rc|
            if action.is_a?(ActionsRules::EventActionWorkflowRun)
              evaluate_workflow_run(action, rc)
            else
              RuleRun.success(rule_config: rc, event_action: action)
            end
          end
        end
      end

      sig { params(action: ActionsRules::EventActionWorkflowRun, rule_config: IRuleConfig).returns(RuleRun) }
      def evaluate_workflow_run(action, rule_config)
        if EXCLUDED_EVENTS.include?(action.event_name)
          return RuleRun.success(rule_config: rule_config, event_action: action)
        end

        allowed_events = rule_config.param("allowed_events").to_a

        if allowed_events.include?(action.event_name)
          RuleRun.success(rule_config: rule_config, event_action: action)
        else
          RuleRun.failure(
            rule_config: rule_config,
            event_action: action,
            message: failure_message_for(action, rule_config),
          )
        end
      end

      sig { params(action: ActionsRules::EventActionWorkflowRun, rule_config: IRuleConfig).returns(String) }
      def failure_message_for(action, rule_config)
        if rule_config.provider_name == RuleEngine::RuleProviders::ImplicitPullRequestTargetRuleProvider::IDENTIFIER &&
            DANGEROUS_EVENT_WARNINGS.key?(action.event_name)
          RuleEngine::RuleProviders::ImplicitPullRequestTargetRuleProvider.failure_message(
            evaluate_mode: rule_config.evaluate_mode?,
          )
        else
          "Event '#{action.event_name}' is not allowed to trigger Actions workflows."
        end
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_source_types
        [:business, :organization, :repository]
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_target_types
        [:actions]
      end
    end
  end
end
