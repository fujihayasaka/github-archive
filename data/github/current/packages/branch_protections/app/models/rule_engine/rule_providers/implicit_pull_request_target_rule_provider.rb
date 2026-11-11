# typed: true
# frozen_string_literal: true

module RuleEngine
  module RuleProviders
    class ImplicitPullRequestTargetRuleProvider < RuleProvider
      IDENTIFIER = "implicit_pull_request_target".freeze

      ENFORCE_FEATURE_FLAG = :pull_request_target_default_disabled_enforce
      EVALUATE_FEATURE_FLAG = :pull_request_target_default_disabled_evaluate

      DISALLOWED_EVENT = "pull_request_target".freeze

      # Workflow Execution Protections active-enforcement date (WEP GA on 2026-07-16 is evaluate mode).
      ENFORCEMENT_DATE = T.let(Date.new(2026, 7, 30).freeze, Date)

      sig { returns(String) }
      def self.formatted_enforcement_date
        ENFORCEMENT_DATE.strftime("%B %-d, %Y")
      end

      sig { params(evaluate_mode: T::Boolean).returns(String) }
      def self.failure_message(evaluate_mode:)
        docs_id = RuleEngine::Rules::RestrictActionsEventsRule::DANGEROUS_EVENT_WARNINGS
          .fetch(DISALLOWED_EVENT).fetch(:docs_url_id)
        docs_url = DocsUrlConfig.url_for(docs_id)

        if evaluate_mode
          "On #{formatted_enforcement_date}, GitHub will restrict `#{DISALLOWED_EVENT}` on " \
            "public repositories by default. To continue allowing the event trigger, " \
            "configure an Actions policy. Learn more: #{docs_url}"
        else
          "GitHub restricts `#{DISALLOWED_EVENT}` on public repositories by default. " \
            "To allow the event trigger, configure an Actions policy. Learn more: #{docs_url}"
        end
      end

      sig { params(source: RuleEngine::Types::RuleSource).returns(T.nilable(Symbol)) }
      def self.activation_state_for(source)
        new.send(:activation_state_for_source, source)
      end

      sig { void }
      def initialize
        super(identifier: IDENTIFIER)
      end

      sig { override.params(event: RuleEvent).returns(T::Array[IRuleConfig]) }
      def rules_for_event(event)
        return [] unless event.is_a?(ActionsRules::WorkflowRunEvent)

        state = activation_state_for_source(event.repository)
        return [] if state.nil?

        allowed_events = RuleEngine::Rules::RestrictActionsEventsRule::ALLOWED_EVENTS_LIST - [DISALLOWED_EVENT]
        config = RuntimeRuleConfig.new(
          provider: self,
          source: event.repository,
          rule_type: "restrict_action_events",
          parameters: { "allowed_events" => allowed_events },
          evaluate_mode: state == :evaluate,
        )
        # PerRuleStrategy uses matching_event_actions to filter configs by dispatched action.
        config.matching_event_actions = event.event_actions
        [config]
      end

      sig { override.params(targetables: T::Enumerable[Targeting::Targetable]).returns(T::Hash[Targeting::Targetable, T::Array[IRuleConfig]]) }
      def rules_for_targetables(targetables)
        # UI surfacing is handled by `activation_state_for`, not a synthetic targetable rule.
        {}
      end

      private

      sig { params(source: RuleEngine::Types::RuleSource).returns(T.nilable(Symbol)) }
      def activation_state_for_source(source)
        # Public-only: fork-based attacks happen here. Private/internal default to forks-disabled.
        return nil if source.is_a?(Repository) && !source.public?

        state = if owner_enabled?(ENFORCE_FEATURE_FLAG, source)
          :enforce
        elsif owner_enabled?(EVALUATE_FEATURE_FLAG, source)
          :evaluate
        end
        return nil if state.nil?

        rulesets = Actions.domain.rulesets.load_rulesets(source, targets: ["actions"], include_inherited: true)
        return nil if rulesets.any? { |rs| overriding_ruleset?(rs, source) }

        state
      end

      # Enrolling an ancestor covers its public descendants. Hand-rolled because vexi has no native
      # owner cascade and feature_enabled_for_repo_or_owner? is repo-only and raises on undefined flags.
      sig { params(flag: Symbol, source: RuleEngine::Types::RuleSource).returns(T::Boolean) }
      def owner_enabled?(flag, source)
        return true if FeatureFlag.vexi.enabled?(flag, source, default: false)

        owner = source.is_a?(Repository) ? source.owner : nil
        return true if owner && FeatureFlag.vexi.enabled?(flag, owner, default: false)

        org = source.is_a?(Organization) ? source : owner
        business = org.is_a?(Organization) ? org.business : nil
        return false if business.nil?

        FeatureFlag.vexi.enabled?(flag, business, default: false)
      end

      # A ruleset suppresses the implicit provider when either:
      #   * it is at the same source -- the customer owns this scope regardless of enforcement, OR
      #   * it is inherited from a parent AND is actively enforcing or evaluating.
      # A *disabled* inherited ruleset does NOT suppress: the parent has no active protection,
      # so the implicit provider must fill the gap (UI banner and workflow enforcement).
      sig { params(ruleset: RuleEngine::IRuleset, source: RuleEngine::Types::RuleSource).returns(T::Boolean) }
      def overriding_ruleset?(ruleset, source)
        return false unless ruleset.rule_configurations.any? { |rc| rc.rule_type == "restrict_action_events" }
        return true if ruleset.source == source
        !ruleset.disabled?
      end
    end
  end
end
