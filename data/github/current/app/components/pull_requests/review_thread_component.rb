# typed: true
# frozen_string_literal: true

module PullRequests
  class ReviewThreadComponent < ApplicationComponent
    include DiffHelper
    include UploadHelper
    include CodeScanningHelper

    ARIA_LABEL_EXPAND = "Expand comment"
    ARIA_LABEL_COLLAPSE = "Collapse comment"

    sig { returns(PullRequest) }
    attr_reader :pull_request

    attr_reader :pull_request_review_thread, :review_thread_or_comment, :rendering_on_files_tab

    def self.preload_review_threads(review_threads:, viewer:, pull_request:)
      GitHub::PrefillAssociations.prefill_associations(review_threads, :pull_request, available_records: pull_request)
      GitHub::PrefillAssociations.prefill_associations(review_threads, :repository, available_records: pull_request.repository)

      GitHub::PrefillAssociations.prefill_batch_method(review_threads, :prelude_paginated_review_comments_for, viewer, PullRequests::ReviewThreadBodyComponent.pagination_params)
      GitHub::PrefillAssociations.prefill_batch_method(review_threads, :prelude_all_review_comments, viewer)
      GitHub::PrefillAssociations.prefill_batch_method(review_threads, :prelude_viewer_can_resolve, viewer)
      GitHub::PrefillAssociations.prefill_batch_method(review_threads, :prelude_viewer_can_unresolve, viewer)

      Promise.all(review_threads.map do |thread|
        promises = [
          thread.async_original_diff_file_path_with_fragment,
          thread.async_locked_for?(viewer),
          thread.async_resolver,
          GitHub.flipper[:remove_side_from_thread_reply].enabled? ? Promise.resolve(nil) : thread.async_diff_side,
        ]
        if !thread.on_file?
          promises.concat(
            [
              thread.async_start_side,
              thread.async_safe_line,
              thread.async_original_start_line,
            ]
          )
        end
        promises
      end.flatten).sync
    end

    def initialize(review_thread_or_comment:, pull_request:, rendering_on_files_tab: false)
      @pull_request = pull_request
      @review_thread_or_comment = review_thread_or_comment
      @rendering_on_files_tab = rendering_on_files_tab

      if review_thread_or_comment.is_a?(PullRequestReviewComment)
        @pull_request_review_thread = review_thread_or_comment.pull_request_review_thread
      else
        @pull_request_review_thread = review_thread_or_comment
      end
    end

    def resource_path
      original_path =
        if pull_request_review_thread.pull_request_review&.applies_to_current_diff?
          pull_request_review_thread.async_original_diff_file_path_with_fragment.sync
        end
      "#{pull_request_path_uri}#{original_path || pull_request_review_thread.current_diff_file_path_with_fragment}"
    end

    memoize def resolved_by_actor
      pull_request_review_thread.async_resolver_for(current_user).sync
    end

    memoize def filename
      reverse_truncate(pull_request_review_thread.path, length: 95).strip
    end

    memoize def collapse_reason_message
      return "resolved" if resolved?
      return "fixed" if fixed_code_scanning_alert?
      return "dismissed" if dismissed_code_scanning_alert?
      "outdated"
    end

    def deferred_content_url
      return unless collapse_by_default?

      repo = pull_request.repository
      return unless repo

      review_thread_path(repo.owner, pull_request.repository, pull_request, pull_request_review_thread.id, rendering_on_files_tab: rendering_on_files_tab)
    end

    def resolved_thread_comments_ids
      return unless resolved?

      pull_request_review_thread.prelude_all_review_comments(current_user).pluck(:id).join(",")
    end

    memoize def resolved?
      pull_request_review_thread.resolved?
    end

    memoize def fixed_code_scanning_alert?
      return false if code_scanning_review_comment.nil?
      code_scanning_review_comment.fixed?
    end

    memoize def dismissed_code_scanning_alert?
      alert = code_scanning_alert
      return false unless alert.present?
      resolution = alert.result&.resolution
      resolution && resolution != :NO_RESOLUTION
    end

    sig { returns(T.nilable(Turboscan::Proto::AnnotationResult)) }
    memoize def code_scanning_alert
      comment = thread_first_comment
      return nil if comment.nil?
      pull_request.code_scanning_alert_for_review_comment(comment)
    end

    memoize def code_scanning_review_comment
      comment = thread_first_comment
      return unless comment
      pull_request.code_scanning_review_comment_for_comment(comment.id)
    end

    def collapse_by_default?
      # Should be collapsed by default ALWAYS if it's resolved.
      return true if resolved?

      # If it's NOT a code scanning alert comment then it should only be collapsed if it's resolved
      return false if !pull_request_review_thread.code_scanning?

      # If it's a code scanning alert comment and it's a conversation (it has replies) it should also
      # only be collapsed if it's resolved (we automatically resolve upon dismissal if there are already
      # replies at that point)
      return false if pull_request_review_thread.conversation?

      # If it's a code scanning alert comment and it's NOT a conversation (it has no replies) it should
      # only be collapsed by default if it's dismissed or fixed.
      fixed_code_scanning_alert? || dismissed_code_scanning_alert?
    end

    def test_selector
      return unless pull_request_review_thread.outdated?
      "is-outdated"
    end

    memoize def pull_request_path_uri
      pull_request.async_path_uri.sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    def summary_hidden?
      rendering_on_files_tab && !collapse_by_default?
    end

    def summary_aria_label
      summary_hidden? ? ARIA_LABEL_EXPAND : ARIA_LABEL_COLLAPSE
    end

    private

    def thread_first_comment
      @pull_request_review_thread.prelude_all_review_comments(current_user).first
    end
  end
end
