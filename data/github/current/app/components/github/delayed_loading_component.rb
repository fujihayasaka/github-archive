# typed: true
# frozen_string_literal: true

module GitHub
  # Component intended to contain a loading element.  Whatever content it wraps
  # will be hidden for a configurable amount of time.
  class DelayedLoadingComponent < ApplicationComponent
    attr_reader :show_after_ms

    def initialize(show_after_ms: 500)
      @show_after_ms = Integer(show_after_ms)
    end
  end
end
