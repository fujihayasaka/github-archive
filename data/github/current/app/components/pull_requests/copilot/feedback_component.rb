# typed: true
# frozen_string_literal: true

module PullRequests
  module Copilot
    class FeedbackComponent < ApplicationComponent

      attr_accessor :comment_id, :feedback_path, :feedback_options, :additional_parameters, :use_ccr_listener

      def initialize(comment_id:, feedback_path:, feedback_options:, additional_parameters: {}, use_ccr_listener: false)
        @comment_id = comment_id
        @feedback_path = feedback_path
        @feedback_options = feedback_options
        @additional_parameters = additional_parameters
        @use_ccr_listener = use_ccr_listener
      end

      private

      def ccr_listener_enabled?
        user_feature_enabled?(:ccr_feedback_listener) && @use_ccr_listener
      end
    end
  end
end
