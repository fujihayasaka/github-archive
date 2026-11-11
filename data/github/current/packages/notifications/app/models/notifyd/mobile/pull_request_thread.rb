# typed: true
# frozen_string_literal: true

module Notifyd
  module Mobile
    class PullRequestThread
      include Thread

      sig { params(pull_request: ::PullRequest).void }
      def initialize(pull_request:)
        @pull_request = pull_request
      end

      sig { override.returns(T.nilable(String)) }
      def id
        @pull_request.permalink(include_host: false)
      end

      sig { override.returns(String) }
      def type
        "pull_request"
      end
    end
  end
end
