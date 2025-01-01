# typed: true
# frozen_string_literal: true

module PullRequests
  module Copilot
    # TODO: yeah, the name
    class CodeReviewCommentOccurrencePullRequestLinkComponent < ViewComponent::Base
      attr_reader :pull_request
      def initialize(pull_request:)
        @pull_request = pull_request
      end

      def icon
        pr_icon.octicon_name
      end

      def icon_tooltip
        pr_icon.label
      end

      def icon_class
        "color-fg-#{pr_icon.primer_color}"
      end

      def pr_icon
        return @pull_request_icon if defined?(@pull_request_icon)
        @pull_request_icon = PullRequest::Icon.new(
          pull_request,
          permit_queued_icon: true,
        )
      end
    end
  end
end
