# typed: true
# frozen_string_literal: true

module Discussions
  class NestedCommentComponent < ApplicationComponent
    def initialize(comment:, error_message: nil, timeline:)
      @comment = comment
      @error_message = error_message
      @timeline = timeline
    end

    private

    attr_reader :comment, :error_message, :timeline

    delegate :minimized?, to: :comment, private: true
  end
end
