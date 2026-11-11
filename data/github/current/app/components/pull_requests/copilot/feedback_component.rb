# typed: true
# frozen_string_literal: true

module PullRequests
  module Copilot
    class FeedbackComponent < ApplicationComponent

      attr_accessor :comment_id, :feedback_path, :feedback_options, :additional_parameters

      def initialize(comment_id:, feedback_path:, feedback_options:, additional_parameters: {})
        @comment_id = comment_id
        @feedback_path = feedback_path
        @feedback_options = feedback_options
        @additional_parameters = additional_parameters
      end
    end
  end
end
