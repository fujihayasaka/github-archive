# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    class IssueComment < Newsies::Emails::Message
      def self.matches?(comment)
        comment.is_a?(::IssueComment) && !T.must(comment.issue).pull_request?
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
        return false unless super && settings.try(:notify_comment_email?)

        opts = @options || {}
        actor = opts[:author]
        trigger = opts[:is_update] ? "updated" : "created"
        if IssueDeliveryCheck.new(issue, actor, settings_user, trigger).notifyd_enabled?
          @undeliverable_reason = "notifyd_enabled"
          return false
        end

        true
      end

      def body
        if settings&.user.feature_enabled?(:newsies_plain_content_header)
          [content_header_plain(action_text: "left a comment"), super].join("\n\n")
        else
          super
        end
      end

      def body_html
        if settings&.user.feature_enabled?(:newsies_hidden_content_header)
          :issue_comment_html
        else
          super
        end
      end

      def content_header_html
        if settings&.user.feature_enabled?(:newsies_hidden_content_header)
          content_header_with_avatar(action_text: "left a comment")
        else
          super
        end
      end
    end
  end
end
