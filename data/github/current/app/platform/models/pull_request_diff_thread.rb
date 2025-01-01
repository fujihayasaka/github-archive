# typed: true
# frozen_string_literal: true

class Platform::Models::PullRequestDiffThread
  include GitHub::Relay::GlobalIdentification

  DELEGATE_METHODS = [
    :async_diff_lines,
    :async_diff_side,
    :async_hide_from_user?,
    :async_line,
    :async_end_line,
    :async_original_line,
    :async_pull_request_commit,
    :async_pull_request,
    :async_start_line,
    :path
  ]

  # review_thread is an instance of a PullRequestReviewThread (AR model)
  attr_reader :review_thread
  delegate *DELEGATE_METHODS, to: :review_thread

  def initialize(review_thread)
    @review_thread = review_thread
  end

  def async_start_line_number
    review_thread.async_start_line.then do |start_line_number|
      start_line_number || review_thread.async_line
    end.then do |line|
      if line.is_a?(GitHub::Diff::Line)
        line.current
      else
        line
      end
    end
  end

  def async_original_start_line
    review_thread.async_original_start_line.then do |original_start_line_number|
      original_start_line_number || review_thread.async_original_line
    end
  end

  def start_side
    review_thread.start_side || review_thread.side
  end

  def path_digest
    Digest::SHA256.hexdigest(review_thread.path)
  end
end
