# typed: true
# frozen_string_literal: true

module Notifyd
  module Mobile
    class IssueThread
      include Thread

      sig { params(issue: ::Issue).void }
      def initialize(issue:)
        @issue = issue
      end

      sig { override.returns(T.nilable(String)) }
      def id
        @issue.permalink(include_host: false)
      end

      sig { override.returns(String) }
      def type
        "issue"
      end
    end
  end
end
