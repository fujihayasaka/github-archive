# typed: true
# frozen_string_literal: true

class RecallAnalysisJob < ApplicationJob
  queue_as :recall_analysis

  retry_on_dirty_exit

  before_enqueue do |job|
    pull_request_id, subject_user_id = job.arguments
    pull_request = PullRequest.find_by(id: pull_request_id)
    throw(:abort) unless pull_request && PullRequests::Copilot::CodeReview::RecallAnalyzer::Analyzer.eligible?(pull_request, subject_user_id)
  end

  sig { params(pull_request_id: Integer, subject_user_id: T.nilable(Integer)).void }
  def perform(pull_request_id, subject_user_id = nil)
    ActiveRecord::Base.connected_to(role: :reading) do
      pull_request = PullRequest.find_by(id: pull_request_id)
      return unless pull_request

      analyzer = PullRequests::Copilot::CodeReview::RecallAnalyzer::Analyzer.new(
        pull_request: pull_request,
        subject_user_id: subject_user_id,
      )
      analyzer.analyze
    end
  end
end
