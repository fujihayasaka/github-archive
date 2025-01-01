# typed: true
# frozen_string_literal: true

module Conduit
  module EventAdapter
    class PullRequest < Conduit::StratocasterEventAdapter
      BODY_MAX_LENGTH = 150
      BODY_HTML_CONTEXT = { context: {} }.freeze

      def html_url
        url
      end

      def title
        T.bind(self, T.untyped)
        if pull_request.merged?
          "#{actor.display_login} contributed to #{repo_nwo}"
        else
          description
        end
      end

      def partial_path
        "events/pull_request"
      end

      def repo_nwo
        repository.name_with_display_owner
      end

      def pull_request_number
        pull_request.number
      end

      def issue_number
        pull_request_number
      end

      def url
        pull_request.permalink
      end

      def octicon_class
        case
        when pull_request.merged?
          "merge"
        when pull_request.closed?
          "pull-request-closed"
        else
          "pull-request"
        end
      end

      def pull_title
        pull_request.title
      end

      def pull_request_body
        pull_request.body
      end

      def icon
        "git-#{octicon_class}"
      end

      def formatted_pull_request_body
        if pull_request_body.present?
          truncated_body_html
        end
      end

      def total_additions
        pull_request.historical_comparison.diffs.additions
      end

      def total_deletions
        pull_request.historical_comparison.diffs.deletions
      end

      def pull_request_comments_count
        pull_request.total_comments
      end

      def action
        T.bind(self, T.untyped)
        first_action = action_string.split(" ").first
        case first_action
        when "contributed"
          "merged"
        when "requested"
          "review requested"
        else
          first_action
        end
      end

      private

      def pull_request
        T.bind(self, T.untyped)
        subject
      end

      def repository
        T.bind(self, T.untyped)
        pull_request.repository
      end

      def body_html
        pull_request.prelude_body_html(BODY_HTML_CONTEXT)
      end

      def truncated_body_html
        body_truncator.to_html(wrap: false)
      end

      def body_truncator
        HTMLTruncator.new(body_html, BODY_MAX_LENGTH, keep_svg_elements: true, strip_block_elements: false)
      end
    end
  end
end
