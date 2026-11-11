# typed: true
# frozen_string_literal: true

module PullRequests
  module Copilot
    class ScheduledSummariesFeedbackCleanupJob < ApplicationJob
      EXPIRED_DAYS = 28

      queue_as :scheduled_summaries_feedback_cleanup

      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      sig { void }
      def perform
        with_write do
          ::Copilot::CompletionFeedback.where("created_at < ?", EXPIRED_DAYS.days.ago).destroy_all
        end
      end
    end
  end
end
