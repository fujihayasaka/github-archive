# typed: true
# frozen_string_literal: true

module Discussions
  class AnswerPreviewComponent < ApplicationComponent
    attr_reader :timeline, :answer, :preview_body

    def initialize(timeline:)
      @timeline     = timeline
      @answer       = timeline&.selected_answer
      @preview_body = timeline&.selected_answer_preview_body
    end

    private

    def render?
      timeline.present? && answer.present?
    end
  end
end
