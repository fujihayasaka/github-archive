# typed: true
# frozen_string_literal: true

module PullRequests
  module Copilot
    class IntroPopoverComponent < ApplicationComponent
      attr_accessor :pull_request, :user, :suggestion, :review_request, :automatic

      def initialize(pull_request:, user:, suggestion: nil, review_request: nil, automatic: false)
        @pull_request = pull_request
        @user = user
        @suggestion = suggestion
        @review_request = review_request
        @automatic = automatic
      end

      def render?
        return false unless user.present?
        return false unless suggestion&.copilot? || review_request&.deferred_copilot?
        pull_request&.new_record? && !dismissed_notice?
      end

      def dismissed_notice?
        if automatic
          user.dismissed_notice?(:copilot_code_review_automatic_reviewer)
        else
          user.dismissed_notice?(:copilot_code_review_suggested_reviewer)
        end
      end

      def dismiss_url
        if automatic
          dismiss_notice_path(:copilot_code_review_automatic_reviewer)
        else
          dismiss_notice_path(:copilot_code_review_suggested_reviewer)
        end
      end

      def heading
        if automatic
          "Copilot will review this pull request"
        else
          "Copilot can review pull requests"
        end
      end

      def body_text
        if automatic
          "Automatic code review from Copilot is enabled in this repository. Copilot will give you fast, actionable feedback on your code, so you can start iterating before you receive a human review. You can request re-review at any time."
        else
          "Request a review from Copilot to get fast, actionable feedback on your code, so you can start iterating before you receive a human review."
        end
      end
    end
  end
end
