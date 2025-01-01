# typed: true
# frozen_string_literal: true

module Notifyd
  module Mobile
    class CheckSuiteThread
      extend T::Sig
      include Thread

      sig { params(check_suite: ::CheckSuite, pull_request: T.nilable(::PullRequest)).void }
      def initialize(check_suite:, pull_request:)
        @check_suite = check_suite
        @pull_request = pull_request
      end

      sig { override.returns(T.nilable(String)) }
      def id
        return @pull_request.permalink(include_host: false) if @pull_request

        @check_suite.permalink(include_host: false)
      end

      sig { override.returns(String) }
      def type
        "ci_activity"
      end
    end
  end
end
