# typed: true
# frozen_string_literal: true

module IssueComment::Prefillable
  extend ActiveSupport::Concern

  class_methods do
    include GitHub::Tracing

    trace_method :prefill_associations
    def prefill_associations(comments, preload_comment_edits: false, current_user: nil, available_records: [], exclude_prefills: [], repository: nil)

      GitHub.tracer.in_span("GitHub::PrefillAssociations.prefill_associations") do
        GitHub::PrefillAssociations.prefill_associations(
          comments,
          [:user, :performed_via_integration, :repository, { issue: [:pull_request, :repository] }],
          available_records: available_records
        )
      end

      Reaction::Summary.prefill(comments)

      if preload_comment_edits
        GitHub.tracer.in_span("GitHub::PrefillAssociations.prefill_batch_method") do
          GitHub::PrefillAssociations.prefill_batch_method(comments,
            :prelude_body_html,
            FeedCards::CommentViewComponentMethods::BODY_HTML_CONTEXT,
          )
        end
      end

      unless exclude_prefills.include?(:author_association)
        IssuePrefiller.preload_author_associations(comments, current_user)
      end
    end
  end
end
