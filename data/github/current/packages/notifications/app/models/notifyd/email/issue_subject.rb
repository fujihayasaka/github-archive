# typed: strict
# frozen_string_literal: true

module Notifyd
  module Email
    class IssueSubject
      extend T::Sig

      sig { params(issue: ::Issue, repository: T.nilable(::Repository)).void }
      def initialize(issue:, repository: nil)
        @issue = issue
        @repository = repository
      end

      sig { returns(String) }
      def serialize
        "[#{repository&.name_with_display_owner}] #{issue.title} (Issue ##{issue.number})"
      end

      private

      sig { returns(::Issue) }
      attr_reader :issue
      sig { returns(T.nilable(::Repository)) }
      attr_reader :repository
    end
  end
end
