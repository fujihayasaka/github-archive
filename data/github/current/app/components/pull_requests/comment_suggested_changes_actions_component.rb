# typed: true
# frozen_string_literal: true

module PullRequests
  class CommentSuggestedChangesActionsComponent < ApplicationComponent
    include SuggestedChangesAnalyticsHelper
    include GitHub::Memoizer
    include ResilienceHelper

    GIT_LOAD_NULL_SHA = "0000000000000000000000000000000000000000"

    attr_reader :comment, :pull_request, :batch_suggestions_disabled, :pull_request_review_thread

    def initialize(comment:, pull_request:, batch_suggestions_disabled: false)
      @comment = comment
      @pull_request = pull_request
      @batch_suggestions_disabled = batch_suggestions_disabled
      @pull_request_review_thread = comment.pull_request_review_thread
    end

    def commit_suggestion_modal_id
      "commit-suggestion-modal-#{comment.id}"
    end

    def viewer_can_apply_suggestion?
      pull_request.suggested_change_applicable_by?(current_user) && pull_request.head_repository && pull_request.head_ref
    end

    def render?
      pull_request_review_thread && viewer_can_apply_suggestion?
    end

    def batch_suggestions_disabled?
      batch_suggestions_disabled || comment.selection_contains_deletions?
    end

    def apply_suggested_changes_path
      pull_request_apply_suggestions_path(pull_request.repository.owner_display_login, pull_request.repository, pull_request.number)
    end

    memoize def current_head_oid
      with_database_error_fallback(fallback: GIT_LOAD_NULL_SHA) do
        pull_request.current_head_oid
      end
    end

    def current_head_oid_loaded?
      current_head_oid != GIT_LOAD_NULL_SHA
    end

    def batch_suggestions_label
      if batch_suggestions_disabled
        "Batching suggestions must be done from the files tab."
      elsif comment.selection_contains_deletions?
        "Applying suggestions on deleted lines is not supported."
      else
        "Add this suggestion to a batch that can be applied as a single commit."
      end
    end
  end
end
