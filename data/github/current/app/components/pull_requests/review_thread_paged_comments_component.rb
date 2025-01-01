# typed: true
# frozen_string_literal: true

module PullRequests
  class ReviewThreadPagedCommentsComponent < ApplicationComponent
    attr_reader :pull_request, :pull_request_review_thread, :page_info, :comment_context

    def initialize(pull_request_review_thread:, pull_request:, page_info:, comment_context: "discussion")
      @pull_request = pull_request
      @pull_request_review_thread = pull_request_review_thread
      @page_info = page_info
      @comment_context = comment_context
    end

    private

    def pagination_path
      review_thread_more_comments_path(
        pull_id: pull_request.number,
        thread_id: pull_request_review_thread.id,
        after: after,
        before: before
      )
    end

    def hidden_comment_ids
      (page_info[:hidden_comment_ids] || []).join(",")
    end

    memoize def after
      page_info[:first_group].last&.id
    end

    memoize def before
      page_info[:before].presence || page_info[:last_group].first&.id
    end

    def comment_variant(comment)
      case comment.pull_request_review&.variant_type
      when "code_scanning"
        if comment.reply? || pull_request.code_scanning_review_comment_for_comment(comment.id).nil?
          PullRequests::ReviewCommentComponent
        else
          CodeScanning::ReviewCommentComponent
        end
      when "copilot"
        PullRequests::Copilot::ReviewCommentComponent
      when "dependabot"
        if pull_request.repository.dependabot_autofix_enabled?
          Dependabot::ReviewCommentComponent
        else
          PullRequests::ReviewCommentComponent
        end
      else
        PullRequests::ReviewCommentComponent
      end
    end
  end
end
