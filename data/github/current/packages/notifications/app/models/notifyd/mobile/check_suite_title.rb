# typed: strict
# frozen_string_literal: true

module Notifyd
  module Mobile
    class CheckSuiteTitle

      sig { params(check_suite: ::CheckSuite, pull_request: T.nilable(::PullRequest)).void }
      def initialize(check_suite:, pull_request:)
        @check_suite = check_suite
        @pull_request = pull_request
      end

      sig { returns(String) }
      def to_s
        verb = StatusCheckConfig.verb_state(@check_suite.conclusion)

        return "Run #{verb}" unless @pull_request
        "PR run #{verb}"
      end
    end
  end
end
