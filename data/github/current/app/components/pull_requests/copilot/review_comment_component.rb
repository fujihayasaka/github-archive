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
          { label: "Comment is a duplicate of another comment", value: "DUPLICATE" },
          { label: "Code suggestion is harmful or unsafe", value: "SUGGESTION_OFFENSIVE_OR_DISCRIMINATORY" },
          { label: "Code suggestion is poorly formatted", value: "SUGGESTION_POORLY_FORMATTED" },
          { label: "Code suggestion does not solve the problem in the comment", value: "SUGGESTION_UNHELPFUL" },
          { label: "Code suggestion is invalid", value: "SUGGESTION_INVALID" }
        ]
      end

      def copilot_code_review_footnote
        if custom_repo_instruction
          return references_footnote(REPO_CUSTOM_INSTRUCTIONS_DOCS_LINK, "repository")
        end

        if custom_org_instruction
          return references_footnote(ORG_CUSTOM_INSTRUCTIONS_DOCS_LINK, "organization")
        end

        DEFAULT_FOOTNOTE_TEXT
      end

      memoize def custom_repo_instruction
        if pull_request_review_comment.copilot_repo_instruction_preloaded?
          return pull_request_review_comment.preloaded_copilot_repo_instruction
        end

        custom_instructions_by_type["repo"]
      end

      memoize def custom_org_instruction
        if pull_request_review_comment.copilot_org_instruction_preloaded?
          return pull_request_review_comment.preloaded_copilot_org_instruction
        end

        custom_instructions_by_type["org"]
      end

      memoize def custom_instructions_by_type
        instruction_types = []
        instruction_types << "repo" unless pull_request_review_comment.copilot_repo_instruction_preloaded?
        instruction_types << "org" unless pull_request_review_comment.copilot_org_instruction_preloaded?
        return {} if instruction_types.empty?

        PullRequests::Copilot::CodeReviewComment.where(
          subject: pull_request_review_comment,
          repository: pull_request.repository,
          copilot_instruction_type: instruction_types
        ).index_by(&:copilot_instruction_type)
      end

      def individual_comment_permalink
        anchor = diff_comment_id(pull_request_review_comment, comment_context)
        "#{pull_request_url(pull_request)}##{anchor}"
      rescue
        nil
      end
    end
  end
end
