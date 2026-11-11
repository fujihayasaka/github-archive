# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    class IssueComment < Newsies::Emails::Message
      def self.matches?(comment)
        comment.is_a?(::IssueComment) && !T.must(comment.issue).pull_request? # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end

      sig { returns(T.nilable(::Issue)) }
      def issue
        T.let(comment, ::IssueComment).issue
      end

      def subject
        "Re: [#{repository.name_with_display_owner}] #{issue&.title}#{issue_subject_suffix}"
      end

      def in_reply_to
        issue&.message_id
      end

      def deliverable?
        return false unless super

        opts = @options || {}
        actor = opts[:author]
        trigger = opts[:is_update] ? "updated" : "created"
        if IssueDeliveryCheck.new(issue, actor, user, trigger).notifyd_enabled?
          @undeliverable_reason = "notifyd_enabled"
          return false
        end

        true
      end

      def body
        [content_header_plain(action_text: "left a comment"), super].join("\n\n")
      end

      def body_html
        :issue_comment_html
      end

      def content_header_html
        content_header_with_avatar(action_text: "left a comment")
      end

      sig { returns T.nilable(String) }
      def content_html
        # At this point we know the generated content is HTML as it has gone through
        # our internal HTML pipelines and in some cases like "email" formatters it has
        # been escaped
        super&.html_safe # rubocop:disable Rails/OutputSafety
      end

      def headers
        is_pr = issue&.pull_request?

        super.merge(
          "X-GitHub-Labels" => issue&.labels&.map(&:name)&.join("; ") || "",
          "X-GitHub-Milestone" => issue&.milestone&.title,
          "X-GitHub-Assignees" => issue&.assignees&.map(&:display_login)&.join("; ") || "",
          "X-GitHub-IssueType" => issue&.issue_type&.name,
          "X-GitHub-IssueState" => (is_pr ? nil : issue&.state),
          "X-GitHub-PullRequestStatus" => (is_pr ? issue&.pull_request&.state&.to_s : nil)
        )
      end
    end
  end
end
