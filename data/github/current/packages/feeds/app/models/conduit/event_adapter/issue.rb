# typed: true
# frozen_string_literal: true

module Conduit
  module EventAdapter
    class Issue < Conduit::StratocasterEventAdapter
      LABELED_ACTION = :labeled
      BODY_MAX_LENGTH = 150

      def html_url
        T.bind(self, T.untyped)
        issue.url
      end

      def partial_path = "events/issues"

      def labeled_event?
        T.bind(self, T.untyped)
        action&.to_sym == LABELED_ACTION
      end

      def title
        T.bind(self, T.untyped)
        if labeled_event? && label_name
          "#{actor} #{action_string} #{label_name} in #{repository.name}"
        else
          "#{actor} #{action_string} in #{repository.name}"
        end
      end

      def repo_nwo = repository.name_with_display_owner

      def octicon_name
        issue_state == "closed" ? "issue-closed" : "issue-opened"
      end

      def issue_state = issue.state

      def number = issue.number

      def url = "/#{repo_nwo}/issues/#{number}"

      def issue_number = number

      def issue_body = issue.body

      def formatted_issue_body
        if issue_body.present?
          HTMLTruncator.new(issue_body, BODY_MAX_LENGTH).to_html(wrap: false)
        end
      end

      def issue_comments_count
        comments_count = issue.comments
        comments_count.count if comments_count.present?
      end

      def icon
        "issues_#{action}"
      end

      def label_color
        issue.labels.first&.color.presence
      end

      def label_name
        issue.labels.first&.name.presence
      end

      private

      def issue
        T.bind(self, T.untyped)
        subject
      end

      def action
        T.bind(self, T.untyped)
        payload_action.to_s
      end

      def repository
        T.bind(self, T.untyped)
        subject.repository
      end
    end
  end
end
