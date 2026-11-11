# typed: true
# frozen_string_literal: true

module Hooks
  class DestroyConfirmationComponent < ApplicationComponent
    attr_reader :hook

    def initialize(hook:, render_button: false)
      @hook = hook
      @render_button = render_button
    end

    def render_button?
      @render_button
    end
  end
end
