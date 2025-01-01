# typed: true
# frozen_string_literal: true

module PullRequests
  module Copilot
    class ReviewCommentComponent < PullRequests::ReviewCommentComponent
      DEFAULT_DOCS_LINK = DocsUrlConfig.url_for("copilot/copilot-code-review-rai")
      DEFAULT_FOOTNOTE_TEXT = "<a href=\"#{DEFAULT_DOCS_LINK}\" class=\"Link--inTextBlock\" target=\"_blank\" rel=\"noopener noreferrer\">Copilot</a> uses AI. Check for mistakes."
      REPO_CUSTOM_INSTRUCTIONS_DOCS_LINK = DocsUrlConfig.url_for("copilot/add-repo-custom-instructions")
      ORG_CUSTOM_INSTRUCTIONS_DOCS_LINK = DocsUrlConfig.url_for("copilot/add-org-custom-instructions")
      FOOTNOTE_BUFFER_CHARACTER = "  ·  "
      CUSTOM_INSTRUCTIONS_FOOTNOTE_TEXT = "Copilot generated this review using guidance from <a href=\"#{REPO_CUSTOM_INSTRUCTIONS_DOCS_LINK}\" class=\"Link--inTextBlock\" target=\"_blank\" rel=\"noopener noreferrer\">copilot-instructions.md</a>."

      def references_footnote(docs_link, type)
        "Copilot generated this review using guidance from <a href=\"#{docs_link}\" class=\"Link--inTextBlock\" target=\"_blank\" rel=\"noopener noreferrer\">#{type} custom instructions</a>."
      end

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
        custom_instruction_footnote_enabled = current_copilot_user_v2&.beta_features_github_chat_enabled? || user_or_global_feature_enabled?(:copilot_code_review_repo_copilot_instructions)

        if custom_instruction_footnote_enabled && custom_repo_instruction
          unless pull_request.repository.feature_flag_enabled?(:ccr_repo_instructions_md, default: false)
            return CUSTOM_INSTRUCTIONS_FOOTNOTE_TEXT
          end
          return references_footnote(REPO_CUSTOM_INSTRUCTIONS_DOCS_LINK, "repository")
        end

        if custom_org_instruction
          return references_footnote(ORG_CUSTOM_INSTRUCTIONS_DOCS_LINK, "organization")
        end

        footnote_text = DEFAULT_FOOTNOTE_TEXT.dup
        # If feature flag is disabled, display default text
        unless user_or_global_feature_enabled?(:copilot_coding_guidelines)
          return footnote_text
        end

        # If code review comment is associated with a coding guideline, add generic attribution text
        if coding_guideline
          footnote_text.prepend("Custom guideline in #{pull_request.repository.name_with_display_owner}#{FOOTNOTE_BUFFER_CHARACTER}")

          # If we'll be displaying the guideline name before the footnote, add the buffer character
          if show_guideline_name_as_text? || show_guideline_name_as_link?
            footnote_text.prepend(FOOTNOTE_BUFFER_CHARACTER)
          end
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

      memoize def custom_repo_instruction
        PullRequests::Copilot::CodeReviewComment.find_by(
          subject: pull_request_review_comment,
          repository: pull_request.repository,
          copilot_instruction_type: "repo"
        )
      end

      memoize def custom_org_instruction
        return unless pull_request.repository.feature_flag_enabled?(:ccr_support_org_instructions, default: false)
        PullRequests::Copilot::CodeReviewComment.find_by(
          subject: pull_request_review_comment,
          repository: pull_request.repository,
          copilot_instruction_type: "org"
        )
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
