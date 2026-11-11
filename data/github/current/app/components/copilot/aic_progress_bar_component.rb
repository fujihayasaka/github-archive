# typed: strict
# frozen_string_literal: true

module Copilot
  class AicProgressBarComponent < ApplicationComponent
    sig { params(percent: Float, label: T.nilable(String)).void }
    def initialize(percent:, label: nil)
      @percent = percent
      @label = label
    end

    sig { returns(Float) }
    def percent
      @percent
    end

    sig { returns(Symbol) }
    def emphasis_color
      if @percent >= 100.0
        :danger_emphasis
      elsif @percent > 75.0
        :attention_emphasis
      else
        :accent_emphasis
      end
    end
  end
end
