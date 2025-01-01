# typed: strict
# frozen_string_literal: true

module CommandPalette
  module Commands
    class SummarizeIssue < ApplicationCommand
      extend T::Sig

      scope_type "Issue"
      display_as "Summarize Issue", icon: "beaker"

      sig { returns(T::Boolean) }
      def enabled?
        current_user.feature_enabled?(:issue_summarization)
      end

      sig { void }
      def execute
        issue = scoped_object
        issue.queue_summary(actor: current_user)
        display_flash(type: :success, message: "Queued summary for Issue: #{issue.title}")
      end
    end
  end
end
