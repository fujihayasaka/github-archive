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
        if IssueDeliveryCheck.new(issue, actor, user, trigger).notifyd_enabled?
          @undeliverable_reason = "notifyd_enabled"
          return false
        end

        true
      end

      def body
        [content_header_plain(action_text: "created an issue"), super].join("\n\n")
      end

      def body_html
        :issue_html
      end

      def content_header_html
        content_header_with_avatar(action_text: "created an issue")
      end

      def headers
        is_pr = issue.pull_request?

        super.merge(
          "X-GitHub-Labels" => issue.labels.map(&:name).join("; "),
          "X-GitHub-Milestone" => issue.milestone&.title,
          "X-GitHub-Assignees" => issue.assignees.map(&:display_login).join("; "),
          "X-GitHub-IssueType" => issue.issue_type&.name,
          "X-GitHub-IssueState" => (is_pr ? nil : issue.state),
          "X-GitHub-PullRequestStatus" => (is_pr ? issue.pull_request&.state&.to_s : nil)
        )
      end
    end
  end
end
