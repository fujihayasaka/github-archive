# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    class GistComment < Newsies::Emails::Message

      def self.matches?(comment)
        comment.is_a?(::GistComment)
      end

      def deliverable?
        return false unless super

        if notifyd_enabled?
          @undeliverable_reason = "notifyd_enabled"
          return false
        end

        true
      end

      def subject
        "Re: #{gist&.name_with_title}"
      end

      def in_reply_to
        gist&.message_id
      end

      def content_header_html
        content_tag(:strong, "@#{comment.user.display_login}") + " commented on this gist." + tag("hr")
      end

      private

      sig { returns T.nilable(::Gist) }
      def gist
        T.let(comment, ::GistComment).gist
      end

      # Checks if notifications for the recipient are processed by Notifyd.
      # For that feature flag must be enabled for both the comment's user and the recipient.
      def notifyd_enabled?
        notifyd_actor = GitHub.flipper[:notifyd_enable_gist_events_for_actor]
        notifyd_recipient = GitHub.flipper[:notifyd_gist_comment_notify]
        notifyd_actor.enabled?(comment.user) && notifyd_recipient.enabled?(settings_user)
      end
    end
  end
end
