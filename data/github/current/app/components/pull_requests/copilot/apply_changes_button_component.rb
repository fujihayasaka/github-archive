# typed: true
# frozen_string_literal: true

module PullRequests
  module Copilot
    class ApplyChangesButtonComponent < ApplicationComponent
      include GitHub::ResilienceMixin

      sig do
        params(
          comment: T.untyped,
          pull_request: T.untyped,
          comment_permalink: T.nilable(String),
          is_overview_comment: T::Boolean
        ).void
      end
      def initialize(comment:, pull_request:, comment_permalink:, is_overview_comment:)
        @comment = comment
        @pull_request = pull_request
        @comment_permalink = comment_permalink
        @is_overview_comment = is_overview_comment
      end

      private

      sig { returns(T::Boolean) }
      def render?
        PullRequests::Copilot::ApplyChangesHelper.can_apply_changes?(
          comment: @comment,
          pull_request: @pull_request,
          user: current_user,
        )
      end

      sig { returns(T.nilable(Repository)) }
      def repository
        @pull_request&.repository
      end

      # `PullRequest#authored_by_agent?` hits the Copilot cluster (`AgenticApp.agent_for_bot_id`),
      # which is optional. Fall back to `false` so the apply-changes button still renders when
      # Copilot is unavailable instead of 500ing the PR show page.
      sig { returns(T::Boolean) }
      def copilot_authored_pr?
        return false unless @pull_request
        with_database_error_fallback(fallback: false) { @pull_request.authored_by_agent? }
      end

      sig { returns(Integer) }
      def comment_count
        if @comment.is_a?(PullRequestReview)
          @comment.review_threads.size
        else
          0
        end
      end

      sig { returns(T::Array[{ filename: String, message: String }]) }
      def thread_comments
        return [] unless @comment.is_a?(PullRequestReview)

        review_threads = @comment.review_threads
        threads_with_first_comments = review_threads.filter_map do |thread|
          first_comment = thread.comments.first
          next unless first_comment

          [thread, first_comment]
        end

        use_unified_predicate = unified_has_suggestion_predicate_enabled?
        if use_unified_predicate
          first_comments = threads_with_first_comments.map { |_thread, first_comment| first_comment }
          GitHub::PrefillAssociations.prefill_associations(first_comments, :automated_review_comment)
        end

        threads_with_first_comments.filter_map do |thread, first_comment|
          suggestion = nil
          suggestion_html = nil
          suggestion_state = nil
          description_html = nil

          if use_unified_predicate
            has_suggestion = first_comment.has_suggestion?(require_preload: true)
            ar_comment = first_comment.association(:automated_review_comment).target
            if ar_comment.present?
              if ar_comment.suggestion_state == "suggestion_state_present" && ar_comment.suggestion.present?
                suggestion = { diffEntries: ar_comment.suggestion.diff_entries_payload }
                suggestion_state = "present"
                description_html = GitHub::Goomba::MarkdownPipeline.to_html(ar_comment.message) if ar_comment.message.present?
              elsif ar_comment.message.present?
                suggestion_html = GitHub::Goomba::MarkdownPipeline.to_html(ar_comment.message)
              end
            end

            suggestion_html = first_comment.body_html if has_suggestion && ar_comment.nil?
          else
            has_suggestion = first_comment.body_may_contain_suggestion?
            suggestion_html = has_suggestion ? first_comment.body_html : nil

            # For automated review comments (e.g. Copilot code review), suggestions
            # are stored separately rather than embedded in the comment body markdown.
            # Pass the structured suggestion data so the client can render the diff.
            if !has_suggestion
              ar_comment = first_comment.automated_review_comment
              if ar_comment.present?
                if ar_comment.suggestion_state == "suggestion_state_present" && ar_comment.suggestion.present?
                  has_suggestion = true
                  suggestion = { diffEntries: ar_comment.suggestion.diff_entries_payload }
                  suggestion_state = "present"
                  description_html = GitHub::Goomba::MarkdownPipeline.to_html(ar_comment.message) if ar_comment.message.present?
                elsif ar_comment.message.present?
                  has_suggestion = true
                  suggestion_html = GitHub::Goomba::MarkdownPipeline.to_html(ar_comment.message)
                end
              end
            end
          end

          {
            filename: thread.blob_path.to_s,
            message: first_comment.body.to_s,
            permalink: first_comment.permalink(include_host: false),
            hasSuggestion: has_suggestion,
            suggestionHtml: suggestion_html,
            suggestion: suggestion,
            suggestionState: suggestion_state,
            descriptionHtml: description_html,
          }.compact
        end
      end

      sig { returns(T.nilable(String)) }
      def pr_base_path
        helpers.pull_request_path(@pull_request)
      end

      sig { returns(T::Boolean) }
      def implement_suggestion_refresh?
        ApplyChangesHelper.implement_suggestion_refresh?(user: current_user)
      end

      sig { returns(T::Boolean) }
      def unified_has_suggestion_predicate_enabled?
        FeatureFlag.vexi.enabled?(
          :unified_batch_pr_comments,
          [current_user, repository, repository&.owner].compact,
          default: false
        )
      end

      sig { returns(T.nilable(String)) }
      def models_url
        ApplyChangesHelper.models_url(
          repository: repository,
          pull_request: @pull_request,
          user: current_user,
          helpers: helpers,
        )
      end
    end
  end
end
