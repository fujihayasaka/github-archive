# typed: true
# frozen_string_literal: true

module PullRequests
  module Copilot
    class ReviewCommentComponent < PullRequests::ReviewCommentComponent
      DEFAULT_FOOTNOTE_TEXT = "Copilot is powered by AI, so mistakes are possible. Review output carefully before use."
      FOOTNOTE_BUFFER_CHARACTER = "  ·  "

      def feedback_path
        repo_code_review_feedback_path(pull_request.repository.owner_display_login,
          pull_request.repository.name,
          pull_request.number)
      end

      def user_feedback_options
        [
          { label: "Comment is harmful or unsafe", value: "OFFENSIVE_OR_DISCRIMINATORY" },
          { label: "Comment is poorly formatted", value: "POORLY_FORMATTED" },
          { label: "Comment is not true", value: "INCORRECT" },
          { label: "Comment is not helpful", value: "UNHELPFUL" },
          { label: "Comment is attached to the wrong line(s)", value: "INCORRECT_LINE" },
          { label: "Code suggestion is harmful or unsafe", value: "SUGGESTION_OFFENSIVE_OR_DISCRIMINATORY" },
          { label: "Code suggestion is poorly formatted", value: "SUGGESTION_POORLY_FORMATTED" },
          { label: "Code suggestion does not solve the problem in the comment", value: "SUGGESTION_UNHELPFUL" },
          { label: "Code suggestion is invalid", value: "SUGGESTION_INVALID" }
        ]
      end

      def copilot_code_review_footnote
        footnote_text = DEFAULT_FOOTNOTE_TEXT.dup

        # If feature flag is disabled, display default text
        unless user_or_global_feature_enabled?(:copilot_coding_guidelines)
          return footnote_text
        end

        # If there's no associated code_review_comment, display default text
        unless generated_from_guideline?
          return footnote_text
        end

        # If code review comment is associated with a coding guideline, add generic attribution text
        if coding_guideline
          footnote_text.prepend("Custom guideline in #{pull_request.repository.name_with_display_owner}#{FOOTNOTE_BUFFER_CHARACTER}")
        end

        # If we'll be displaying the guideline name before the footnote, add the buffer character
        if show_guideline_name_as_text? || show_guideline_name_as_link?
          footnote_text.prepend(FOOTNOTE_BUFFER_CHARACTER)
        end

        footnote_text
      end

      memoize def coding_guideline
        code_review_comment = \
          PullRequests::Copilot::CodeReviewComment.includes(:copilot_coding_guideline).find_by(
            subject: pull_request_review_comment,
            repository: pull_request.repository
          )

        code_review_comment&.copilot_coding_guideline
      end

      def coding_guideline_edit_url
        edit_copilot_code_guideline_path(
          id: coding_guideline.id,
          repository: pull_request.repository,
          user_id: pull_request.repository.owner_display_login,
        )
      end

      memoize def generated_from_guideline?
        coding_guideline.present?
      end

      # Same permission checks as edit_repositories/copilot_code_guidelines#edit
      memoize def show_guideline_name_as_link?
        return false unless user_or_global_feature_enabled?(:copilot_coding_guidelines)
        return false unless generated_from_guideline?
        return false unless pull_request.repository.adminable_by?(current_user)
        ::Copilot::Organization.new(pull_request.repository.owner).can_use_copilot_enterprise_features?
      end

      memoize def show_guideline_name_as_text?
        return false unless user_or_global_feature_enabled?(:copilot_coding_guidelines)
        return false unless generated_from_guideline?
        return false if show_guideline_name_as_link?
        coding_guideline.name.present?
      end
    end
  end
end
