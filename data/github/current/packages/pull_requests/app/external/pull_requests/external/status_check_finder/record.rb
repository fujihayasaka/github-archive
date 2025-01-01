# typed: strict
# frozen_string_literal: true

module PullRequests
  module External
    class StatusCheckFinder
      # Wraps a `StatusCheckType` (e.g. `Status`, `InMemoryRequiredStatusCheck`)
      # with some additional data that can only be derived from the combination
      # of the check and the rules.
      #
      # The things that require additional data from the rules are:
      #
      # - `#required?` -- indicates if there was a rule that requires this
      #    check.
      # - `#rule_evaluation_result` -- for requried checks, indicates the
      #   result of the rule engine's evaluation. A check might be successful
      #   but still fail to pass the relevant rule, e.g. because it was
      #   reported by the wrong integration.
      class Record
        include Domain::StatusChecks::IStatusCheck

        sig do
          params(
            check: StatusCheckType,
            rule_evaluation_result: Domain::StatusChecks::RuleEvaluationResult,
          ).void
        end
        def initialize(check, rule_evaluation_result:)
          @check = check
          @rule_evaluation_result = rule_evaluation_result
        end

        sig { override.returns(Domain::StatusChecks::RuleEvaluationResult) }
        attr_reader :rule_evaluation_result

        sig { override.returns(T::Boolean) }
        def required? = rule_evaluation_result.required?

        sig { override.returns(String) }
        def context = @check.context

        sig { override.returns(String) }
        def contextual_name = @check.contextual_name

        sig { override.returns(T.nilable(String)) }
        def description = @check.description

        sig { override.returns(Integer) }
        def duration_in_seconds = @check.duration_in_seconds

        sig { override.returns(String) }
        def state = @check.state

        sig { override.returns(Time) }
        def state_changed_at = @check.state_changed_at.to_time

        sig { override.params(pull_request: T.nilable(IPullRequest)).returns(T.nilable(String)) }
        def target_url(pull_request = nil)
          case @check
          when CombinedStatus::CheckRunAdapter
            @check.target_url(pull: pull_request)
          when RuleEngine::Rules::WorkflowRule::RequiredWorkflowStatusCheckDuckType,
            RequiredStatusCheck, InMemoryRequiredStatusCheck
            @check.target_url(pull_request_number: pull_request&.number)
          when Status
            @check.target_url
          else
            T.absurd(@check)
          end
        end

        sig { override.params(size: Integer).returns(T.nilable(String)) }
        def avatar_url(size)
          if application = self.application
            application.preferred_avatar_url(size:)
          elsif creator = self.creator
            creator.primary_avatar_url(size)
          elsif integration = self.integration
            integration.bot&.primary_avatar_url(size)
          else
            nil
          end
        end

        sig { override.returns(T.nilable(OauthApplication)) }
        def application = @check.application

        sig { override.returns(T.nilable(User)) }
        def creator = @check.creator

        sig { override.returns(T.nilable(Integer)) }
        def integration_id
          case @check
          when CombinedStatus::CheckRunAdapter, Status, InMemoryRequiredStatusCheck, RequiredStatusCheck
            @check.integration_id
          when RuleEngine::Rules::WorkflowRule::RequiredWorkflowStatusCheckDuckType
            nil
          else
            T.absurd(@check)
          end
        end

        sig { override.returns(T.untyped) }
        def integration
          @check.integration
        end

        sig { override.returns(T.nilable(CheckSuite)) }
        def check_suite
          case @check
          when CombinedStatus::CheckRunAdapter, RuleEngine::Rules::WorkflowRule::RequiredWorkflowStatusCheckDuckType
            @check.check_suite
          when Status, InMemoryRequiredStatusCheck, RequiredStatusCheck
            nil
          else
            T.absurd(@check)
          end
        end

        sig { override.returns(T.nilable(Integer)) }
        def check_suite_id
          case @check
          when CombinedStatus::CheckRunAdapter
            @check.check_suite_id
          when RuleEngine::Rules::WorkflowRule::RequiredWorkflowStatusCheckDuckType
            @check.check_suite&.id
          when Status, InMemoryRequiredStatusCheck, RequiredStatusCheck
            nil
          else
            T.absurd(@check)
          end
        end

        sig { override.returns(T.nilable(CombinedStatus::CheckRunAdapter)) }
        def as_check_run
          case @check
          when CombinedStatus::CheckRunAdapter
            @check
          when RuleEngine::Rules::WorkflowRule::RequiredWorkflowStatusCheckDuckType,
            Status, InMemoryRequiredStatusCheck, RequiredStatusCheck
            nil
          else
            T.absurd(@check)
          end
        end
      end
    end
  end
end
