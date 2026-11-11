# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    class IssueEventNotification < Newsies::Emails::Message
      def self.matches?(comment)
        comment.is_a?(::IssueEventNotification)
      end

      delegate :issue, to: :comment # domain-isolation-query-violation:ignore:packages/issues (SELECT)

      def subject
        "Re: [#{repository.name_with_display_owner}] #{issue.title}#{issue_subject_suffix}"
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

      def in_reply_to
        if issue.pull_request?
          issue.pull_request.message_id
        else
          issue.message_id
        end
      end

      def deliverable?
        return false unless super

        opts = @options || {}
        actor = opts[:author]
        trigger = comment.issue_event.event
        if IssueDeliveryCheck.new(issue, actor, user, trigger).notifyd_enabled?
          @undeliverable_reason = "notifyd_enabled"
          return false
        end

        true
      end

      def content
        if comment.respond_to?(:body_plaintext_for_email)
          comment.body_plaintext_for_email
        else
          super
        end
      end

      def content_html
        comment.body_html(context: {
          for_email: true,
          body_pipeline: GitHub::Goomba::EmailPipeline,
          current_user: user,
        })
      end
    end
  end
end
