# typed: strict
# frozen_string_literal: true

module RuleEngine
  module RuleProviders
    class PushRulesetRuleProvider < GitRulesetRuleProvider
      include BypassDelegation

      sig { void }
      def initialize
        super(identifier: "push_ruleset")
      end

      sig { override.returns(Types::Phase) }
      def phase
        Types::Phase::PreReceive
      end

      sig { override.params(repository: Repository).returns(T::Array[RepositoryRuleset]) }
      def load_rulesets(repository)
        RepositoryRuleset.load_for(source: repository, include_parents: true, targets: %w(push))
      end

      # push rulesets are not loaded for BranchRuleEvaluator
      sig { override.params(repository: Repository, ref_names: T::Array[String]).returns(T::Array[RepositoryRuleConfiguration]) }
      def rule_for_branch_evaluators(repository, ref_names)
        if GitHub.flipper[:skip_push_rulesets_for_branch_evaluator].enabled?(repository)
          []
        else
          super
        end
      end

      sig do
        override.params(
          rule_config: RepositoryRuleConfiguration,
          actor: Types::Actor,
          repository: Repository,
          rule_run: T.nilable(RuleRun)
        ).returns(T::Boolean)
      end
      def can_bypass?(rule_config, actor, repository, rule_run = nil)
        result = super

        # Delegated bypass is only supported for specific runs, not in general against a rule
        return result unless rule_run && rule_run.ref_update.present?

        # Delegated bypass for forked repos is only support if the pusher has access to the root repo
        if repository.fork?
          return result unless repository.network&.root&.readable_by?(actor)
        end

        rule_run.delegation_metadata ||= {}
        if !rule_config.repository_ruleset&.supports_delegated_bypass? || result
          # If the actor can bypass this rule but not another rule, still allow delegation
          if result
            T.must(rule_run.delegation_metadata)[:delegation_allowed] = true
          end
          return result
        end

        # If a bypass was already approved for this push, we don't need to check again
        # This is necessary because bypass is re-evaluated for pre-receive rules in the post-receive step
        suite_requests = rule_run.rule_suite&.exemption_requests_used&.filter { |request| request.request_type == "push_ruleset_bypass" }
        if suite_requests&.any?(&:completed?)
          return true
        end

        T.must(rule_run.delegation_metadata)[:delegation_allowed] = true

        request = Exemptions::ExemptionRequest.pending.not_expired.order(created_at: :desc).find_by(
          request_type: "push_ruleset_bypass",
          resource_identifier: rule_run.ref_update&.after_oid,
          repository_id: repository.fork? ? repository.network&.root_id : repository.id,
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

      sig do
        override.params(
          rule_suite: RuleSuite,
          event: RuleEvent
        ).void
      end
      def on_evaluation_complete(rule_suite, event)
        return unless rule_suite.persisted?
        return unless event.is_a?(GitEvent) && event.is_writing?

        failed_runs = rule_suite.rule_runs.filter(&:failed?).filter { |rule_run| rule_run.rule_provider == identifier }
        return if failed_runs.empty?

        failed_runs.each do |failed_run|
          valid_response_ids = failed_run.delegation_metadata&.[](:valid_responses)&.map(&:id)
          if valid_response_ids&.any?
            failed_run.evaluation_metadata["exemption_responses"] = valid_response_ids
          else
            failed_run.evaluation_metadata.delete("exemption_responses")
          end
          failed_run.save
        end

        if rule_suite.failed?
          allows_delegation = failed_runs.all? do |rule_run|
            rule_run.delegation_metadata&.[](:delegation_allowed)
          end

          # We can have requests marked to be used and the suite still fails if other rules are failing
          used_requests = failed_runs.filter_map do |rule_run|
            rule_run.delegation_metadata&.[](:used_request)
          end

          # Requests that are awaiting approval and were not used
          pending_requests = failed_runs.filter_map do |rule_run|
            rule_run.delegation_metadata&.[](:pending_request)
          end

          rule_changed = failed_runs.any? do |rule_run|
            rule_run.delegation_metadata&.[](:rule_changed)
          end

          if pending_requests.size == failed_runs.size
            message = "(!) Push protection bypass request(s) pending approval:\n"
            message += pending_requests.uniq.map do |request|
              "- #{push_ruleset_bypass_url(request)}"
            end.join("\n")
            rule_suite.additional_cli_message = message
          # Only give a bypass URL if all rules support delegation and all rule bypasses aren't already approved
          elsif used_requests.size < failed_runs.size && allows_delegation
            url = create_push_ruleset_bypass_url(rule_suite)
            rule_suite.additional_cli_message = "(?) To push, resolve push protection violations or follow this URL to request push protection bypass.\n#{url}"
          end

          if rule_changed
            message = "\n(!) Some rules have changed since a bypass request was created. New bypass requests are required when a rule changes"
            if rule_suite.additional_cli_message
              rule_suite.additional_cli_message = T.must(rule_suite.additional_cli_message) + message
            else
              rule_suite.additional_cli_message = message
            end
          end
        # Only mark requests as completed if all rules were bypassable
        # Unless we are in the final evaluation phase (PostReceive), don't mark requests as used
        # This is to ensure when bypass is re-evaluated for the final phase we can use these requests
        elsif rule_suite.bypassed? && event.phase == Types::Phase::PostReceive
          used_requests = failed_runs.filter_map do |rule_run|
            rule_run.delegation_metadata&.[](:used_request)
          end.uniq

          return unless used_requests.any?

          used_requests.each do |request|
            request.status = :completed
            request.save
          end

          rule_suite.evaluation_metadata["used_exemption_requests"] = used_requests.map(&:id)
          rule_suite.save

          message = "Push protection bypass request(s) utilized:\n"
          message += used_requests.map do |request|
            a = "- #{push_ruleset_bypass_url(request)}\n"
            a += request.responses.group_by(&:status).map do |status, responses|
              "   #{status.capitalize} by: #{responses.map { |response| response.reviewer.display_login }.join(", ")}"
            end.join("\n")
          end.join("\n")
          rule_suite.additional_cli_message = message
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
