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
    end
  end
end
