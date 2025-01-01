# typed: strict
# frozen_string_literal: true

module PullRequests
  module External
    module Domain
      class StatusChecks
        class RuleEvaluationResult < T::Enum
          extend T::Sig

          enums do
            # From `RuleEngine::StatusCheckEvaluator::StatusCheckResult::CODES`
            Missing = new(:missing)
            Unsuccessful = new(:unsuccessful)
            InvalidIntegration = new(:invalid_integration)
            Success = new(:success)

            # The rule engine ignores checks that are not required
            NotRequired = new(:not_required)
          end

          sig { returns(T::Boolean) }
          def required?
            case self
            when Missing, Unsuccessful, InvalidIntegration, Success
              true
            when NotRequired
              false
            else
              T.absurd(self)
            end
          end

          sig { returns(T::Boolean) }
          def pass?
            case self
            when Success, NotRequired
              true
            when Missing, Unsuccessful, InvalidIntegration
              false
            else
              T.absurd(self)
            end
          end

          sig { returns(T::Boolean) }
          def fail? = !pass?
        end
      end
    end
  end
end
