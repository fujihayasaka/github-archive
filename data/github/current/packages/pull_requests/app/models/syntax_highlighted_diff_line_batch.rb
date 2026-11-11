# typed: true
# frozen_string_literal: true

class SyntaxHighlightedDiffLineBatch
  MAX_CONTEXT_LINES = PullRequests::ReviewThreadDiffLinesComponent::MAX_CONTEXT_LINES

  def initialize(pull_request_id, review_thread_ids)
    @pull_request_id = pull_request_id
    @review_thread_ids = review_thread_ids
  end

  def as_json(*_)
    threads = pull_request_review_threads_by_id.values
    return {} if threads.empty?

    first_thread = threads.first
    pull_request = first_thread.pull_request
    repository = pull_request.repository

    use_cotd = FeatureFlag.vexi.enabled?(:prx_comment_outside_the_diff, repository, repository.owner, default: false)

    if use_cotd
      # Use the batch method for comments outside the diff
      promises = @review_thread_ids.map do |key, review_thread_id|
        review_thread = pull_request_review_threads_by_id[review_thread_id]
        next unless review_thread

        review_thread.async_batch_prelude_diff_lines_outside_diff(pull_request, { max_context_lines: MAX_CONTEXT_LINES, cache_only: false }).then do |diff_lines|
          [key, diff_lines]
        end
      end

      Promise.all(promises).sync.compact.to_h
    else
      # Use the original method
      promises = @review_thread_ids.map do |key, review_thread_id|
        review_thread = pull_request_review_threads_by_id[review_thread_id]
        next unless review_thread

        review_thread.async_diff_lines(max_context_lines: MAX_CONTEXT_LINES).then do |diff_lines|
          [key, diff_lines]
        end
      end

      Promise.all(promises).sync.compact.to_h
    end
  end

  private

  def pull_request_review_threads_by_id
    @pull_request_review_threads_by_id ||= PullRequestReviewThread.on_line.where(
      pull_request_id: @pull_request_id,
      id: @review_thread_ids.values,
    ).index_by(&:id)
  end
end
