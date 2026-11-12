# typed: true
# frozen_string_literal: true

require "monolith-twirp-dependabot-pullrequests"

module GitHub
  module Twirp
    class DependabotPullRequests
      module Helpers
        extend T::Sig

        APIErrorType = MonolithTwirp::Dependabot::PullRequests::V1::ErrorType
        EligibilityResult = MonolithTwirp::Dependabot::PullRequests::V1::CheckPullRequestEligibilityResponse::Result
        CiStatus = MonolithTwirp::Dependabot::PullRequests::V1::CiStatus

        sig { params(type: T.any(Symbol, Integer)).returns(Symbol) }
        def resolve_api_error_symbol(type)
          return type if type.is_a?(Symbol)

          T.must(APIErrorType.lookup(type) || APIErrorType.lookup(APIErrorType::ERROR_TYPE_INVALID))
        end

        sig { params(type: T.any(Symbol, Integer)).returns(Integer) }
        def resolve_api_error_number(type)
          return type if type.is_a?(Integer)

          T.must(APIErrorType.resolve(type) || APIErrorType::ERROR_TYPE_INVALID)
        end

        sig { params(result: T.any(Symbol, Integer)).returns(Symbol) }
        def resolve_pr_eligibility_result_symbol(result)
          return result if result.is_a?(Symbol)

          T.must(EligibilityResult.lookup(result) || EligibilityResult.lookup(EligibilityResult::RESULT_INVALID))
        end

        sig { params(result: T.any(Symbol, Integer)).returns(Integer) }
        def resolve_pr_eligibility_result_number(result)
          return result if result.is_a?(Integer)

          T.must(EligibilityResult.resolve(result) || EligibilityResult::RESULT_INVALID)
        end

        sig { params(result: T.any(Symbol, Integer)).returns(Symbol) }
        def resolve_ci_status_symbol(result)
          return result if result.is_a?(Symbol)

          T.must(CiStatus.lookup(result) || CiStatus.lookup(CiStatus::CI_STATUS_INVALID))
        end
      end
    end
  end
end
