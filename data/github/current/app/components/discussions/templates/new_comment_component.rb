# typed: true
# frozen_string_literal: true

module Discussions
  module Templates
    class NewCommentComponent < ApplicationComponent
      def initialize(can_comment:, timeline:, repository:, slash_commands_enabled: false)
        @can_comment = can_comment
        @timeline = timeline
        @discussion = timeline.discussion
        @repository = repository
        @slash_commands_enabled = slash_commands_enabled
      end

      private

      attr_reader :timeline, :discussion, :repository

      def render?
        @can_comment
      end

      def slash_commands_enabled?
        @slash_commands_enabled
      end
    end
  end
end
