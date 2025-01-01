# typed: true
# frozen_string_literal: true

module PullRequests
  class ReviewThreadDiffLinesComponent < ApplicationComponent
    include DiffHelper
    include EditorConfigHelper

    MAX_CONTEXT_LINES = 3

    attr_reader :pull_request_review_thread, :highlighting_mode

    def initialize(pull_request_review_thread:, highlighting_mode: nil)
      @pull_request_review_thread = pull_request_review_thread
      @highlighting_mode = highlighting_mode
    end

    memoize def diff_lines
      pull_request_review_thread.prelude_diff_lines(
        max_context_lines: MAX_CONTEXT_LINES,
        cache_only: should_defer_syntax_highlighting?
      )
    end

    def context_lines
      pull_request_review_thread.diff_entry&.context_lines
    end

    def found_highlighted_lines_in_cache?
      diff_lines.all? { _1[:cache_code] != :miss }
    end

    def pull_request
      pull_request_review_thread.pull_request
    end

    def repository
      pull_request.base_repository
    end

    def deferred_syntax_url
      pull_request_review_thread_syntax_highlighted_diff_lines_path(repository.owner, repository, pull_request)
    end

    def deferred_syntax_inputs
      { pull_request_review_thread_id: @pull_request_review_thread.id }
    end

    private

    def should_defer_syntax_highlighting?
      highlighting_mode.nil? || highlighting_mode == Diffs::DeferredDiffLinesComponent::HighlightingModes::DEFERRED
    end
  end
end
