# typed: true
# frozen_string_literal: true

module RuleEngine
  module RuleProviders
    class RepositoryPolicyRuleProvider < RulesetRuleProvider

      def initialize
        super(identifier: "repository_policy")
      end

      sig { override.params(event: RuleEvent).returns(T::Array[RepositoryRuleset]) }
      def load_rulesets_for_event(event)
        return [] unless event.is_a?(Events::RepositoryOperationEvent)
        return [] unless event.feature_enabled?(:member_privilege_rulesets)

        owner = event.repository_model.owner
        if owner.is_a?(Organization)
          RepositoryRuleset.load_for(source: owner, include_parents: true, targets: ["repository"], check_conditions_on_parent_rulesets: false)
        elsif owner.is_a?(User) && owner.is_enterprise_managed? && owner.enterprise_managed_business.present?
          RepositoryRuleset.load_for(source: owner.enterprise_managed_business, include_parents: true, targets: ["repository"], check_conditions_on_parent_rulesets: false)
        else
          []
        end
      end

      sig { override.params(targetables: T::Enumerable[Conditions::Targetable]).returns(T::Array[RepositoryRuleset]) }
      def load_rulesets_for_targetables(targetables)
        targetables.map do |targetable|
          targetable.get_attribute(Conditions::Targetable::Attribute::Organization) ||
            targetable.get_attribute(Conditions::Targetable::Attribute::User)
        end.uniq.map do |owner|
          if owner.is_a?(Organization)
            RepositoryRuleset.load_for(source: owner, include_parents: true, targets: ["repository"], check_conditions_on_parent_rulesets: false)
          elsif owner.is_a?(User) && owner.is_enterprise_managed?
            RepositoryRuleset.load_for(source: owner.enterprise_managed_business, include_parents: true, targets: ["repository"], check_conditions_on_parent_rulesets: false)
          else
            []
          end
        end.flatten.uniq
      end

      sig do
        override.params(
          rule_config: RepositoryRuleConfiguration,
          actor: Types::Actor,
          targetable: RuleEngine::Conditions::Targetable,
          rule_run: T.nilable(RuleRun)
        ).returns(T::Boolean)
      end
      def can_bypass?(rule_config, actor, targetable, rule_run = nil)
        result = super

        # Delegated bypass is only supported for specific runs, not in general against a rule
        return result unless rule_run

        repository = targetable.get_attribute(Conditions::Targetable::Attribute::Repository)
        return result unless repository

        rule_run.delegation_metadata ||= {}
        if !rule_config.repository_ruleset&.supports_delegated_bypass? || result
          # If the actor can bypass this rule but not another rule, still allow delegation
          if result
            T.must(rule_run.delegation_metadata)[:delegation_allowed] = true
          end
          return result
        end

        # If a bypass was already approved for this action, we don't need to check again
        # This is necessary because bypass is re-evaluated for pre-receive rules in the post-receive step
        suite_requests = rule_run.rule_suite&.exemption_requests_used&.filter { |request| request.request_type == "repository_policy_ruleset_bypass" }
        if suite_requests&.any?(&:completed?)
          return true
        end

        T.must(rule_run.delegation_metadata)[:delegation_allowed] = true

        request = Exemptions::ExemptionRequest.pending.not_expired.order(created_at: :desc).find_by(
          request_type: "repository_policy_ruleset_bypass",
          resource_identifier: rule_run.rule_suite&.id,
          repository_id: repository.id,
          requester: actor,
        )

        # If a pending request does not exist, deny bypass
        # If all rules support delegation, a request URL will be generated in `on_evaluation_complete`
        return false unless request

        # Ensure this rule was evaluated before. If a new rule is present, the bypass approval must be re-requested
        previous_suite = T.cast(request.resource_owner, RuleSuite)
        previous_run = previous_suite.rule_runs.to_ary.compact.find { |old_run| rule_runs_match?(old_run, rule_run) }
        unless previous_run
          T.must(rule_run.delegation_metadata)[:rule_changed] = true
          return false
        end

        request_status = request.compute_status

        # compute_status notes which responses applied to which runs in the previous suite. This is important because for
        # each ruleset, we need to show which user authorized bypass. Rulesets might have different authorized bypassers.
        T.must(rule_run.delegation_metadata)[:valid_responses] = previous_run.delegation_metadata&.[](:valid_responses)

        case request_status
        when Exemptions::ExemptionEvaluator::EvaluationResult::Approved
          T.must(rule_run.delegation_metadata)[:used_request] = request
          true
        else
          T.must(rule_run.delegation_metadata)[:pending_request] = request
          false
        end
      end

      sig { params(run1: RuleRun, run2: RuleRun).returns(T::Boolean) }
      private def rule_runs_match?(run1, run2)
        run1.result == run2.result &&
          run1.rule_type == run2.rule_type &&
          run1.rule_provider == run2.rule_provider &&
          run1.rule_provider_id == run2.rule_provider_id &&
          run1.rule_history_id == run2.rule_history_id
      end
    end
  end
end
