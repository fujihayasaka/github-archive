# typed: true
# frozen_string_literal: true

class SyntaxHighlightedDiffLineBatch
  MAX_CONTEXT_LINES = PullRequests::ReviewThreadDiffLinesComponent::MAX_CONTEXT_LINES

  def initialize(pull_request_id, review_thread_ids)
    @pull_request_id = pull_request_id
    @review_thread_ids = review_thread_ids
  end

  def as_json(*_)
    promises = @review_thread_ids.map do |key, review_thread_id|
      review_thread = pull_request_review_threads_by_id[review_thread_id]
      next unless review_thread

      review_thread.async_diff_lines(max_context_lines: MAX_CONTEXT_LINES).then do |diff_lines|
        [key, diff_lines]
      end
    end

    Promise.all(promises).sync.compact.to_h
  end

  private

  def pull_request_review_threads_by_id
    @pull_request_review_threads_by_id ||= PullRequestReviewThread.on_line.where(
      pull_request_id: @pull_request_id,
      id: @review_thread_ids.values,
    ).index_by(&:id)
  end
end
