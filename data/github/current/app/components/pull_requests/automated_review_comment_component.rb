# typed: true
# frozen_string_literal: true

module PullRequests
  class AutomatedReviewCommentComponent < ReviewCommentComponent

    # Note(@aliceclv): temporarily untype review comment and pull request params while we find a solution for test preview data.
    sig do
      params(
        pull_request_review_comment: T.untyped,
        pull_request: T.untyped,
        automated_review_comment: ::AutomatedReviewComment,
        comment_context: T.nilable(String)
      ).void
    end
    def initialize(pull_request_review_comment:, pull_request:, automated_review_comment:, comment_context: nil)
      @pull_request = pull_request
      @pull_request_review_comment = pull_request_review_comment
      @automated_review_comment = automated_review_comment
      @comment_context = comment_context
    end

    def automated_review_component_props
      {
        isAnchorable: true,
        anchorPrefix: "discussion_r",
        applySuggestionPath: apply_automated_review_comment_suggestion_path(repository.owner, repository, @pull_request, @automated_review_comment.id),
        isInlineComment: false,
        # Note(@aliceclv): seems like this outdated attribute is not properly referenced in Sorbet
        # We should ask the PR team if we need to support it still
        isOutdated: T.unsafe(@pull_request_review_comment).outdated?,
        comment: {
          author: author_props,
          automatedComment: automated_review_comment_props,
          body: @pull_request_review_comment.body,
          bodyHTML: @pull_request_review_comment.body_html,
          createdAt: @pull_request_review_comment.created_at&.iso8601,
          databaseId: @pull_request_review_comment.id,
          publishedAt: @pull_request_review_comment.created_at&.iso8601,
          id: @pull_request_review_comment.global_relay_id,
          reviewVariantType: "automated",
          state: "visible",
          viewerCanBlockFromOrg: false,
          viewerCanMinimize: false,
          viewerCanSeeMinimizeButton: false,
          viewerCanSeeUnminimizeButton: false,
          viewerCanReact: false,
          viewerCanReport: false,
          viewerCanReportToMaintainer: false,
          viewerCanUnblockFromOrg: false,
          viewerDidAuthor: false,
          viewerRelationship: "none",
          viewerCanDelete: false,
          viewerCanUpdate: false,
          viewerCanReferenceInIssue: false,
          viewerCanQuoteReply: false,
          url: @pull_request_review_comment.url,
          reference: reference_props,
          repository: repository_props
        },
        commentingImplementation: {
          commentSubjectType: "pull request",
        },
        threadId: @pull_request_review_comment.pull_request_review_thread_id,
      }
    end

    private

    def repository
      @pull_request.repository
    end

    def reference_props
      {
        number: @pull_request.number,
        author: {
          login: @pull_request.user&.display_login
        },
        text: nil
      }
    end

    def repository_props
      {
        id: repository&.id.to_s,
        isPrivate: repository&.private?,
        name: repository&.name,
        owner: {
          login: repository&.owner&.display_login
        }
      }
    end

    memoize def author
      @pull_request_review_comment.async_user.then do |user|
        next User.ghost if user.nil? || user.hide_from_user?(current_user)

        user
      end.sync
    end

    def author_props
      {
        id: author.id,
        login: author.display_login,
        avatarUrl: author.primary_avatar_url
      }
    end

    def suggestion_props
      suggestion = @automated_review_comment.suggestion
      return unless suggestion && suggestion.description.present?

      diff_entries = suggestion.diff_entries_payload
      {
        description: suggestion.description,
        diffEntries: diff_entries
      }
    end

    def automated_review_comment_props
      {
        id: @automated_review_comment.id.to_s,
        title: @automated_review_comment.title,
        message: @automated_review_comment.message,
        severity: @automated_review_comment.severity.delete_prefix("severity_"),
        suggestion: suggestion_props,
        suggestionState: @automated_review_comment.suggestion_state.delete_prefix("suggestion_state_")
      }
    end
  end
end
