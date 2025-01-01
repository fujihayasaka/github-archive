# typed: true
# frozen_string_literal: true

require "test_helper"
module PullRequests
  module Copilot
    class ScheduledSummariesFeedbackCleanupJobTest < GitHub::TestCase
      setup do
        @repo = create(:repository)
        @user = create(:user)
        @expired_days = ::PullRequests::Copilot::ScheduledSummariesFeedbackCleanupJob::EXPIRED_DAYS

        @queue = "scheduled_summaries_feedback_cleanup"
      end

      test "deletes feedback older than 28 days" do
        feedback = ::Copilot::CompletionFeedback.new(
              repository: @repo,
              user: @user,
              job_id: 25,
              context: { stuff: "things" },
              created_at: (@expired_days + 1).days.ago
            )
        feedback.save!

        assert_equal 1, ::Copilot::CompletionFeedback.count

        ::PullRequests::Copilot::ScheduledSummariesFeedbackCleanupJob.perform_now

        assert_equal 0, ::Copilot::CompletionFeedback.count
      end

      test "does not delete feedback younger than 90 days" do
        feedback = ::Copilot::CompletionFeedback.new(
              repository: @repo,
              user: @user,
              job_id: 25,
              context: { stuff: "things" },
              created_at: (@expired_days - 1).days.ago
            )
        feedback.save!

        assert_equal 1, ::Copilot::CompletionFeedback.count

        ::PullRequests::Copilot::ScheduledSummariesFeedbackCleanupJob.perform_now

        assert_equal 1, ::Copilot::CompletionFeedback.count
      end
    end
  end
end
