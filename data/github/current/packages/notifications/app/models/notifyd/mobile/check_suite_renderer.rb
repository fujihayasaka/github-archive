# typed: strict
# frozen_string_literal: true

module Notifyd
  module Mobile
    class CheckSuiteRenderer
      extend T::Sig
      Layout = Notifyd::Proto::Layouts::Mobile

      sig do
        params(
          check_suite: ::CheckSuite,
          repository: ::Repository,
          pull_request: T.nilable(::PullRequest),
          attempt: ::Numeric
        ).void
      end
      def initialize(check_suite:, repository:, pull_request:, attempt:)
        @check_suite = check_suite
        @repository = repository
        @pull_request = pull_request
        @attempt = attempt
      end

      sig { returns(Layout::Basic) }
      def render
        thread = CheckSuiteThread.new(check_suite: check_suite, pull_request: pull_request)

        Layout::Basic.new(
          title: CheckSuiteTitle.new(check_suite: check_suite, pull_request: pull_request).to_s,
          subtitle: CheckSuiteSubtitle.new(repository: repository).to_s,
          body: CheckSuiteBody.new(check_suite: check_suite, pull_request: pull_request, attempt: attempt).to_s,
          url: check_suite.permalink,
          thread_id: thread.id,
          thread_type: thread.type,
        )
      end

      private

      sig { returns(::CheckSuite) }
      attr_reader :check_suite
      sig { returns(::Repository) }
      attr_reader :repository
      sig { returns(T.nilable(::PullRequest)) }
      attr_reader :pull_request
      sig { returns(::Numeric) }
      attr_reader :attempt
    end
  end
end
