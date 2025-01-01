# typed: true
# frozen_string_literal: true

module PullRequests
  class ReviewCommentComponent < ApplicationComponent
    include CommentsHelper
    include DiffHelper

    attr_reader :pull_request, :pull_request_review_comment, :render_minimized, :comment_context

    def self.body_html_context(pull_request:, viewer:, cap_filter:)
      {
        viewer: viewer,
        cap_filter: cap_filter,
        unfurl_references: true,
      }
    end

    def self.preload_review_comments(review_comments:, reviews:, pull_request:, viewer:, cap_filter:, timer: nil)
      GitHub::PrefillAssociations.prefill_associations(review_comments, :pull_request, available_records: [pull_request])
      GitHub::PrefillAssociations.prefill_associations(review_comments, :pull_request_review, available_records: reviews)

      if viewer.try(:site_admin?)
        site_admin_promises = [
          Issue::Loader::Base.new.async_preload_attribute(review_comments, :report_count, :async_report_count),
          Issue::Loader::Base.new.async_preload_attribute(review_comments, :top_report_reason, :async_top_report_reason),
          Issue::Loader::Base.new.async_preload_attribute(review_comments, :last_reported_at, :async_last_reported_at),
        ]
        Promise.all(site_admin_promises).sync
      end

      editable = (review_comments + reviews).uniq.compact
      Promise.all(editable.map { |editable| [editable.async_viewer_can_read_user_content_edits?(viewer), editable.async_latest_user_content_edit] }.flatten).sync

      if timer
        timer.track do
          Promise.all(
            editable.map { |associable| CommentAuthorAssociation.new(comment: associable, viewer: viewer).async_to_sym.then { |sym| associable.preload_attr(:author_association_symbol, sym) } }
          ).sync
        end
      else
        Promise.all(
          editable.map { |associable| CommentAuthorAssociation.new(comment: associable, viewer: viewer).async_to_sym.then { |sym| associable.preload_attr(:author_association_symbol, sym) } }
        ).sync
      end

      GitHub::PrefillAssociations.prefill_batch_method(review_comments, :prelude_body_html, context: body_html_context(pull_request: pull_request, viewer: viewer, cap_filter: cap_filter))
      GitHub::PrefillAssociations.prefill_batch_method(review_comments, :prelude_viewer_can_react, viewer)
      GitHub::PrefillAssociations.prefill_batch_method(review_comments, :prelude_user_logins_by_reaction)
    end

    def initialize(pull_request_review_comment:, pull_request:, render_minimized: false, comment_context: "discussion")
      @pull_request = pull_request
      @pull_request_review_comment = pull_request_review_comment
      @render_minimized = render_minimized
      @comment_context = comment_context
    end

    def comment_path
      "#{pull_request_path_uri}/review_comment/#{pull_request_review_comment.id}"
    end

    memoize def pull_request_path_uri
      pull_request.async_path_uri.sync
    end

    def body_html_context
      self.class.body_html_context(
        pull_request: pull_request,
        viewer: current_user,
        cap_filter: cap_filter,
      )
    end

    def action_menu_path
      review_comment_actions_path(
        tab: "discussion",
        user_id: pull_request.repository.owner_display_login,
        repository: pull_request.repository.name,
        id: pull_request_review_comment.global_relay_id,
        pull_id: pull_request.number
      )
    end
  end
end
