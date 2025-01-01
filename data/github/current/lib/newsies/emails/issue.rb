# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    class Issue < Newsies::Emails::Message
      def self.matches?(comment)
        comment.is_a?(::Issue) && !comment.pull_request?
      end

      def comment
        super
      end
      alias issue comment

      def subject
        "[#{repository.name_with_display_owner}] #{comment.title}#{issue_subject_suffix}"
      end

      def deliverable?
        return false unless super

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
          [content_header_plain(action_text: "created an issue"), super].join("\n\n")
        else
          super
        end
      end

      def body_html
        if settings&.user.feature_enabled?(:newsies_hidden_content_header)
          :issue_html
        else
          super
        end
      end

      def content_header_html
        if settings&.user.feature_enabled?(:newsies_hidden_content_header)
          content_header_with_avatar(action_text: "created an issue")
        else
          super
        end
      end
    end
  end
end
