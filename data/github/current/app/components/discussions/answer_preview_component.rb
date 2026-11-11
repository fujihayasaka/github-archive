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

    def answer_timestamp
      if verified_answer?
        answer.discussion.verified_at
      else
        answer.created_at
      end
    end

    def verified_answer?
      timeline.show_as_verified_answer?(answer)
    end

    def regular_answer?
      timeline.show_as_answer?(answer) && !verified_answer?
    end
  end
end
