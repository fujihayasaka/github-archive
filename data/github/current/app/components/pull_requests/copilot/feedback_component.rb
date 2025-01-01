# typed: true
# frozen_string_literal: true

module PullRequests
  module Copilot
    class FeedbackComponent < ApplicationComponent

      attr_accessor :comment_id, :feedback_path, :feedback_options

      def initialize(comment_id:, feedback_path:, feedback_options:)
        @comment_id = comment_id
        @feedback_path = feedback_path
        @feedback_options = feedback_options
      end
    end
  end
end
