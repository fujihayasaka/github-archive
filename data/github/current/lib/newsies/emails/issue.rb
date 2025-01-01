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
        if user.feature_flag_enabled?(:newsies_plain_content_header, default: false)
          [content_header_plain(action_text: "created an issue"), super].join("\n\n")
        else
          super
        end
      end

      def body_html
        if user.feature_flag_enabled?(:newsies_hidden_content_header, default: false)
          :issue_html
        else
          super
        end
      end

      def content_header_html
        if user.feature_flag_enabled?(:newsies_hidden_content_header, default: false)
          content_header_with_avatar(action_text: "created an issue")
        else
          super
        end
      end

      def headers
        if FeatureFlag.vexi.enabled?(:additional_issue_email_headers, user, default: false)
          is_pr = issue.pull_request?

          super.merge(
            "X-GitHub-Labels" => issue.labels.map(&:name).join("; "),
            "X-GitHub-Milestone" => issue.milestone&.title,
            "X-GitHub-Assignees" => issue.assignees.map(&:display_login).join("; "),
            "X-GitHub-IssueType" => issue.issue_type&.name,
            "X-GitHub-IssueState" => (is_pr ? nil : issue.state),
            "X-GitHub-PullRequestStatus" => (is_pr ? issue.pull_request&.state&.to_s : nil)
          )
        else
          super
        end
      end
    end
  end
end
