# typed: true
# frozen_string_literal: true

class Platform::Models::PullRequestThread
  include GitHub::Relay::GlobalIdentification

  # :review_thread is an instance of a PullRequestReviewThread (AR model)
  attr_reader :review_thread

  # Why aren't we just method missing all of these? So that fields we don't want to leak from ActiveRecord never make
  # it to the GraphQL layer.
  DELEGATE_METHODS = [
    :async_can_resolve,
    :async_can_unresolve,
    :async_current_diff_path_uri,
    :async_diff_side,
    :async_hide_from_user?,
    :async_line,
    :async_resolver,
    :async_start_line,
    :async_start_side,
    :async_review_comments_for,
    :async_viewer_can_reply?,
    :async_viewer_cannot_reply_reasons,
    :global_id,
    :id,
    :outdated?,
    :resolved?,
    :path,
    :path_digest,
    :subject_type,
    :created_at,
    :updated_at
  ]

  DELEGATE_METHODS.each do |method_name|
    delegate method_name, to: :review_thread
  end

  def initialize(review_thread)
    @review_thread = review_thread.is_a?(DeprecatedPullRequestReviewThread) ? review_thread.activerecord_pull_review_thread : review_thread
  end

  def async_pull_request
    review_thread.async_pull_request
  end

  def async_repository
    review_thread.async_repository
  end
end
