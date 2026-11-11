# typed: true
# frozen_string_literal: true

class CodeScanning::TrackAutomatedReviewCommentSuggestionJob < ApplicationJob
  queue_as :code_scanning

  use_replicas ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::RepositoriesActionsChecks

  before_perform do |job|
    context = {
      job: job.class.name,
      automated_review_comment_id: job.arguments.first,
    }
    Failbot.push(context)
  end

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { params(automated_review_comment_id: Integer, enqueued_updated_at: Time).void }
  def perform(automated_review_comment_id, enqueued_updated_at)
    automated_review_comment = T.let(pending_suggestion_attempt(automated_review_comment_id, enqueued_updated_at), T.nilable(AutomatedReviewComment))
    return if automated_review_comment.nil?

    with_primaries([ApplicationRecord::IssuesPullRequests]) do
      # Read comment from primary this time
      automated_review_comment = pending_suggestion_attempt(automated_review_comment_id, enqueued_updated_at)
      CodeScanning::AutomatedReviewCommentSuggestionFromTurboscan.sync_or_timeout_pending(automated_review_comment) if automated_review_comment
    end
  end

  sig { params(automated_review_comment: AutomatedReviewComment).void }
  def self.schedule(automated_review_comment)
    repository = automated_review_comment.repository
    return unless repository&.feature_flag_enabled?(:code_scanning_track_automated_review_comment_suggestion, default: false)

    set(wait: 10.minutes).perform_later(automated_review_comment.id, automated_review_comment.updated_at)
  end

  private

  sig { params(automated_review_comment_id: Integer, enqueued_updated_at: Time).returns(T.nilable(AutomatedReviewComment)) }
  def pending_suggestion_attempt(automated_review_comment_id, enqueued_updated_at)
    automated_review_comment = AutomatedReviewComment.find_by(id: automated_review_comment_id, source: :source_code_scanning)
    return if automated_review_comment.nil?
    return unless automated_review_comment.suggestion_state_pending?
    return unless automated_review_comment.updated_at == enqueued_updated_at

    automated_review_comment
  end
end
