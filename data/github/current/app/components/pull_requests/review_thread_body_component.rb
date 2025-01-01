# typed: true
# frozen_string_literal: true

module PullRequests
  class ReviewThreadBodyComponent < ApplicationComponent
    include DiffHelper
    include BlobHelper

    COMMENTS_TO_DISPLAY = 10

    attr_reader :highlighting_mode,
      :pull_request,
      :pull_request_review_thread,
      :render_collapsed,
      :rendering_on_files_tab,
      :reply_only

    def initialize(
      highlighting_mode: nil,
      review_thread_or_comment:,
      pull_request:,
      rendering_on_files_tab: false
    )
      @highlighting_mode = highlighting_mode
      @pull_request = pull_request
      @rendering_on_files_tab = rendering_on_files_tab

      if review_thread_or_comment.is_a?(PullRequestReviewComment)
        @pull_request_review_thread = review_thread_or_comment.pull_request_review_thread
        @reply_only = true
        @page_info = { first_group: [review_thread_or_comment] }
      else
        @reply_only = false
        @pull_request_review_thread = review_thread_or_comment
      end
    end

    memoize def page_info
      @page_info || pull_request_review_thread.prelude_paginated_review_comments_for(current_user, PullRequests::ReviewThreadBodyComponent.pagination_params)
    end

    def comment_context
      rendering_on_files_tab ? "diff" : "discussion"
    end

    memoize def current_comparison
      pull_request_review_thread.current_comparison
    end

    def can_reply?
      return false if reply_only
      return false unless logged_in?
      return false if current_user.must_verify_email?
      return false if pull_request.repository.archived?
      return false if pull_request_review_thread.async_locked_for?(current_user).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)

      true
    end

    def can_unresolve?
      return false if reply_only

      pull_request_review_thread.prelude_viewer_can_unresolve(current_user)
    end

    def can_resolve?
      return false if reply_only

      pull_request_review_thread.conversation? && pull_request_review_thread.prelude_viewer_can_resolve(current_user)
    end

    memoize def resolved_by_actor
      pull_request_review_thread.async_resolver_for(current_user).sync
    end

    def resolve_path
      resolve_review_thread_path(pull_request.repository.owner, pull_request.repository, pull_request, pull_request_review_thread.id)
    end

    def unresolve_path
      unresolve_review_thread_path(pull_request.repository.owner, pull_request.repository, pull_request, pull_request_review_thread.id)
    end

    def reply_preview_path
      preview_path(repository: pull_request.repository, pull_request: pull_request, comment_id: comment_id)
    end

    def reply_textarea_id
      "new_inline_comment_discussion_#{diff_file_anchor(pull_request_review_thread.path)}_#{comment_id}_#{pull_request_review_thread.position}"
    end

    # TODO(dzader): anything using this can probably use thread_id instead
    def comment_id
      page_info[:first_group]&.first&.id
    end

    def slash_commands_enabled?
      current_user.slash_commands_enabled?
    end

    def allows_suggested_changes?
      pull_request_review_thread.on_line?
    end

    memoize def language_from_filename
      filename = reverse_truncate(pull_request_review_thread.path, length: 95).strip
      languages = Linguist::Language.find_by_extension(filename)

      languages.first.name if languages.any?
    end

    memoize def collapse_reason_message
      pull_request_review_thread.resolved? ? "resolved" : "outdated"
    end

    def resolution_info_deletion_class
      return "" unless pull_request_review_thread.code_scanning?
      "js-delete-on-last-reply-deleted"
    end

    def self.pagination_params
      { first: COMMENTS_TO_DISPLAY / 2, last: COMMENTS_TO_DISPLAY / 2 }.freeze
    end

    def line_type_symbol(line_type)
      return nil unless line_type

      case line_type
      when :addition then "+"
      when :deletion then "-"
      else
        ""
      end
    end

    def start_line_number
      rendering_on_files_tab ? pull_request_review_thread.start_line_number : pull_request_review_thread.async_original_start_line.sync
    end

    def end_line_number
      rendering_on_files_tab ? pull_request_review_thread.async_line.sync : pull_request_review_thread.async_original_line.sync
    end

    def start_line_type
      line_type_symbol(pull_request_review_thread.async_start_line.sync&.type)
    end

    def end_line_type
      line_type_symbol(pull_request_review_thread.async_end_line.sync&.type)
    end

    def display_range_info?
      return false if pull_request_review_thread.on_file?
      return false unless start_line_number

      start_line_number != end_line_number
    end

    def pull_request_review
      pull_request_review_thread.pull_request_review
    end
  end
end
