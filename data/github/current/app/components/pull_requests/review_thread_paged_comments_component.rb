# typed: true
# frozen_string_literal: true

module PullRequests
  class ReviewThreadPagedCommentsComponent < ApplicationComponent

    CommentComponentType = T.type_alias do
      T.any(
        T.class_of(PullRequests::ReviewCommentComponent),
        T.class_of(CodeScanning::ReviewCommentComponent),
        T.class_of(PullRequests::Copilot::ReviewCommentComponent),
        T.class_of(Dependabot::ReviewCommentComponent)
      )
    end

    attr_reader :pull_request, :pull_request_review_thread, :page_info, :comment_context

    def initialize(pull_request_review_thread:, pull_request:, page_info:, comment_context: "discussion")
      @pull_request = pull_request
      @pull_request_review_thread = pull_request_review_thread
      @page_info = page_info
      @comment_context = comment_context
    end

    def show_copilot_variant_reply?(comment)
      comment.copilot_reply? &&
        FeatureFlag.vexi.enabled?(:ccr_chat_with_comments, current_user, default: false) &&
        FeatureFlag.vexi.enabled?(:ccr_chat_with_comments, pull_request.repository, default: false)
    end

    def comment_component(pull_request_review_comment:, pull_request:, comment_context:)
      # Basic arguments provided to all components
      base_args = {
        pull_request_review_comment:,
        pull_request:,
        comment_context:,
      }

      component_class, extra_args = comment_variant(
        pull_request_review_comment,
        pull_request
      )

      # Create and return the component with appropriate arguments
      component_class.new(**T.unsafe({ **base_args.merge(extra_args) }))
    end

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

    private

    sig do
      params(
        comment: PullRequestReviewComment,
        pull_request: PullRequest
      ).returns(
        [CommentComponentType, T::Hash[Symbol, T.untyped]]
      )
    end
    def comment_variant(comment, pull_request)
      variant_type = comment.pull_request_review&.variant_type
      is_reply = comment.reply?

      # Default component with no extra arguments
      default_component = [PullRequests::ReviewCommentComponent, {}]

      case variant_type
      when "automated"
        return default_component if is_reply
        return default_component unless CodeQuality.automated_review_comment_enabled?(T.must(pull_request.repository))

        automated_review_comment = pull_request.automated_review_comment_for_review_comment(comment.id)
        return default_component unless automated_review_comment.present?

        [PullRequests::AutomatedReviewCommentComponent, { automated_review_comment: }]
      when "code_quality"
        repository = pull_request.repository
        return default_component unless repository.present? && CodeQuality.enabled?(repository)
        return default_component if is_reply
        return default_component if pull_request.code_quality_finding_for_review_comment(comment.id).nil?

        # Code scanning component with code_quality flag set to true
        [CodeScanning::ReviewCommentComponent, { code_quality: true }]
      when "code_scanning"
        return default_component if is_reply
        return default_component if pull_request.code_scanning_review_comment_for_comment(comment.id).nil?

        # Code scanning component
        [CodeScanning::ReviewCommentComponent, {}]
      when "copilot"
        # Copilot component
        [PullRequests::Copilot::ReviewCommentComponent, {}]
      when "dependabot"
        # Only show Dependabot component if the repository has dependabot autofix enabled
        if pull_request.repository&.dependabot_autofix_enabled?
          [Dependabot::ReviewCommentComponent, {}]
        else
          default_component
        end
      else
        default_component
      end
    end
  end
end
