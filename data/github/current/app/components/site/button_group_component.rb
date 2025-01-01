# typed: true
# frozen_string_literal: true

module Site
  class ButtonGroupComponent < ApplicationComponent
    VERSION = "1.0.0"

    def initialize(buttons: , size: :medium, analytics: nil)
      @buttons = buttons
      @size = size
      @analytics = analytics

      size = @buttons[0][:size].present? ? @buttons[0][:size] : @size
      @buttons.each_with_index do |button, index|
        button[:size] = size
        button[:scheme] = index == 0 ? :default : :muted
        button[:arrow] |= index == 0
        button[:analytics] = @analytics.present? && button[:analytics] ? @analytics.merge(button[:analytics]) : button[:analytics] || @analytics
      end
    end
  end
end
