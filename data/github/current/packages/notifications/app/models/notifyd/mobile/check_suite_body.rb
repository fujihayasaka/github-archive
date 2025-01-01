# typed: strict
# frozen_string_literal: true

module Notifyd
  module Mobile
    class CheckSuiteBody
      extend T::Sig

      sig do
        params(
          check_suite: ::CheckSuite,
          pull_request: T.nilable(::PullRequest),
          attempt: ::Numeric
        ).void
      end
      def initialize(check_suite:, pull_request:, attempt:)
        @check_suite = check_suite
        @pull_request = pull_request
        @attempt = attempt
      end

      sig { returns(String) }
      def to_s
        title = pull_request&.title || check_suite.head_branch
        workflow_name_with_attempt = attempt >= 1 ? "#{check_suite.name}, Attempt ##{attempt}" : check_suite.name

        "#{workflow_name_with_attempt} - #{title} (#{check_suite.short_head_sha})"
      end

      private

      sig { returns(::CheckSuite) }
      attr_reader :check_suite
      sig { returns(T.nilable(::PullRequest)) }
      attr_reader :pull_request
      sig { returns(::Numeric) }
      attr_reader :attempt
    end
  end
end
