# typed: strict
# frozen_string_literal: true

module PullRequests
  module External
    module Domain
      class StatusChecks
        module IStatusCheck
          extend T::Helpers
          extend T::Sig

          interface!

          sig { abstract.returns(Domain::StatusChecks::RuleEvaluationResult) }
          def rule_evaluation_result; end

          sig { abstract.returns(T::Boolean) }
          def required?; end

          sig { abstract.returns(String) }
          def context; end

          sig { abstract.returns(T.nilable(String)) }
          def description; end

          sig { abstract.returns(Integer) }
          def duration_in_seconds; end

          sig { abstract.returns(String) }
          def state; end

          sig { abstract.returns(Time) }
          def state_changed_at; end

          sig { abstract.returns(T.nilable(String)) }
          def target_url; end

          sig { abstract.returns(T.nilable(OauthApplication)) }
          def application; end

          sig { abstract.returns(T.nilable(User)) }
          def creator; end

          sig { abstract.returns(T.untyped) }
          def integration; end

          sig { abstract.returns(T.nilable(CheckSuite)) }
          def check_suite; end

          sig { abstract.returns(T.nilable(Integer)) }
          def check_suite_id; end
        end
      end
    end
  end
end
