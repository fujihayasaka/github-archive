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
        if user.feature_flag_enabled?(:newsies_plain_content_header, default: false)
          [content_header_plain(action_text: "left a comment"), super].join("\n\n")
        else
          super
        end
      end

      def body_html
        if user.feature_flag_enabled?(:newsies_hidden_content_header, default: false)
          :issue_comment_html
        else
          super
        end
      end

      def content_header_html
        if user.feature_flag_enabled?(:newsies_hidden_content_header, default: false)
          content_header_with_avatar(action_text: "left a comment")
        else
          super
        end
      end

      sig { returns T.nilable(String) }
      def content_html
        if user.feature_flag_enabled?(:newsies_issue_comment_email_format_html_fix, default: false)
          # At this point we know the generated content is HTML as it has gone through
          # our internal HTML pipelines and in some cases like "email" formatters it has
          # been escaped
          super&.html_safe # rubocop:disable Rails/OutputSafety
        else
          super
        end
      end

      def headers
        if FeatureFlag.vexi.enabled?(:additional_issue_email_headers, user, default: false)
          is_pr = issue&.pull_request?

          super.merge(
            "X-GitHub-Labels" => issue&.labels&.map(&:name)&.join("; ") || "",
            "X-GitHub-Milestone" => issue&.milestone&.title,
            "X-GitHub-Assignees" => issue&.assignees&.map(&:display_login)&.join("; ") || "",
            "X-GitHub-IssueType" => issue&.issue_type&.name,
            "X-GitHub-IssueState" => (is_pr ? nil : issue&.state),
            "X-GitHub-PullRequestStatus" => (is_pr ? issue&.pull_request&.state&.to_s : nil)
          )
        else
          super
        end
      end
    end
  end
end
