# typed: true
# frozen_string_literal: true

module PullRequests
  class AutomatedReviewCommentComponent < ReviewCommentComponent
    include Reactions::BaseComponentHelpers

    REPO_CUSTOM_INSTRUCTIONS_DOCS_LINK = DocsUrlConfig.url_for("copilot/add-repo-custom-instructions")
    ORG_CUSTOM_INSTRUCTIONS_DOCS_LINK = DocsUrlConfig.url_for("copilot/add-org-custom-instructions")

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
        isAnchorable: false,
        anchorPrefix: "discussion_r",
        basePath: pull_request_path(@pull_request, repository),
        isInlineComment: false,
        # Note(@aliceclv): seems like this outdated attribute is not properly referenced in Sorbet
        # We should ask the PR team if we need to support it still
        isOutdated: T.unsafe(@pull_request_review_comment).outdated?,
        showApplyChangesButton: show_apply_changes_button?,
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
          viewerCanReact: viewer_can_react?,
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
          repository: repository_props,
          reactionGroups: reaction_groups
        },
        commentingImplementation: {
          commentSubjectType: "pull request",
        },
        threadId: @pull_request_review_comment.pull_request_review_thread_id,
        footnoteTextHTML: footnote_text_html,
      }
    end

    private

    def show_apply_changes_button?
      @automated_review_comment.show_apply_changes_button?(
        pull_request: @pull_request,
        pull_request_review_comment: @pull_request_review_comment,
        user: current_user,
      )
    end

    # Target for the Reactions::BaseComponentHelpers module
    def target
      @pull_request_review_comment
    end

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

    memoize def reaction_groups
      loader_reaction_groups = PullRequests::PageData::Helpers::Reactable::Loader.async_reaction_groups(@pull_request_review_comment, current_user).sync
      PullRequests::PageData::Helpers::Reactable::Payload.build_reaction_groups(loader_reaction_groups)
    rescue StandardError => e
      Failbot.report!(e)
      []
    end

    def automated_review_comment_props
      {
        id: @automated_review_comment.id.to_s,
        title: @automated_review_comment.title,
        message: GitHub::Goomba::MarkdownPipeline.to_html(@automated_review_comment.message),
        securitySeverity: @automated_review_comment.security_severity&.delete_prefix("security_severity_"),
        severity: @automated_review_comment.severity.delete_prefix("severity_"),
        source: @automated_review_comment.source.delete_prefix("source_"),
        showFeedbackButtons: @automated_review_comment.show_feedback_buttons?,
        feedbackOptions: @automated_review_comment.feedback_options,
        showAiNote: @automated_review_comment.show_ai_note?,
        dismissalOptions: @automated_review_comment.dismissal_options,
        dismissable: @automated_review_comment.dismissable?,
        delegatedDismissalEnabled: @automated_review_comment.delegated_dismissal_enabled?,
        isDismissed: @automated_review_comment.dismissed?,
        dismissalReason: @automated_review_comment.dismissal_reason,
        dismissedBy: @automated_review_comment.dismissed_by,
        delegatedDismissalRequest: delegated_dismissal_props,
        isFixed: @automated_review_comment.fixed?,
        viewerCanDismiss: current_user.present? && @automated_review_comment.can_dismiss?(user: current_user),
        viewerCanReopen: current_user.present? && @automated_review_comment.can_reopen?(user: current_user),
      }.merge suggestion_props
    end

    def suggestion_props
      suggestion_state = @automated_review_comment.suggestion_state
      formatted_state = suggestion_state.delete_prefix("suggestion_state_")

      # Early return for states without suggestions
      if suggestion_state.in?(%w[
        suggestion_state_no_suggestion
        suggestion_state_pending
        suggestion_state_error
      ])
        return { suggestionState: formatted_state }
      end

      begin
        diff_entries_payload = @automated_review_comment.suggestion&.diff_entries_payload
      rescue ::ReviewComments::Suggestion::ParseError => e
        # report the error to Sentry
        Failbot.report!(e)
      end

      return { suggestionState: "error" } if diff_entries_payload.blank?

      {
        suggestion: {
          diffEntries: diff_entries_payload,
        },
        suggestionState: formatted_state
      }
    end

    def delegated_dismissal_props
      request = @automated_review_comment.current_delegated_dismissal_request
      return nil if request.nil?

      {
        requester: request.requester.name,
        reason: request.reason,
        status: request.status,
        reviewer: request.reviewer&.name
      }
    end

    def footnote_text_html
      return unless @automated_review_comment.source_copilot?

      ccr_comment = PullRequests::Copilot::CodeReviewComment.find_by(
        subject: @pull_request_review_comment,
        repository: @pull_request.repository,
      )

      return unless ccr_comment.present?

      case ccr_comment.copilot_instruction_type
      when "repo"
        references_footnote(REPO_CUSTOM_INSTRUCTIONS_DOCS_LINK, "repository")
      when "org"
        references_footnote(ORG_CUSTOM_INSTRUCTIONS_DOCS_LINK, "organization")
      end
    end

    def references_footnote(docs_link, type)
      "Copilot generated this review using guidance from <a href=\"#{docs_link}\" class=\"Link--inTextBlock\" target=\"_blank\" rel=\"noopener noreferrer\">#{type} custom instructions</a>."
    end
  end
end
