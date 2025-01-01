# typed: strict
# frozen_string_literal: true

module PullRequests
  module External
    module Domain
      class StatusChecks
        module IStatusCheck
          extend T::Helpers

          interface!
          requires_ancestor { Object }

          sig { abstract.returns(Domain::StatusChecks::RuleEvaluationResult) }
          def rule_evaluation_result; end

          sig { abstract.returns(T::Boolean) }
          def required?; end

          sig { abstract.returns(String) }
          def context; end

          sig { abstract.returns(String) }
          def contextual_name; end

          sig { abstract.returns(T.nilable(String)) }
          def description; end

          sig { abstract.returns(Integer) }
          def duration_in_seconds; end

          sig { abstract.returns(String) }
          def state; end

          sig { abstract.returns(Time) }
          def state_changed_at; end

          sig { abstract.params(pull_request: T.nilable(IPullRequest)).returns(T.nilable(String)) }
          def target_url(pull_request = nil); end

          sig { abstract.params(size: Integer).returns(T.nilable(String)) }
          def avatar_url(size); end

          sig { abstract.returns(T.nilable(OauthApplication)) }
          def application; end

          sig { abstract.returns(T.nilable(User)) }
          def creator; end

          sig { abstract.returns(T.nilable(Integer)) }
          def integration_id; end

          sig { abstract.returns(T.untyped) }
          def integration; end

          sig { abstract.returns(T.nilable(CheckSuite)) }
          def check_suite; end

          sig { abstract.returns(T.nilable(Integer)) }
          def check_suite_id; end

          # `CheckRun` has some features that don't exist on `Status`, like
          # the `#rerequest` method which allows for retrying. This method
          # provides a way to access those features if the underlying record
          # is a `CombinedStatus::CheckRunAdapter`.
          sig { abstract.returns(T.nilable(CombinedStatus::CheckRunAdapter)) }
          def as_check_run; end
        end
      end
    end
  end
end
