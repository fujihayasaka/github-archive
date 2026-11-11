# typed: true
# frozen_string_literal: true

module GhostPilot
  # This base-class is used to create async context in the UI
  # via include-fragment elements which defer their loading.
  #
  # * Fragments of context are found by our class in the frontend.
  # * data-src is promoted to full src when loading is desired.
  #   (currently when we're actually visible in the page)
  class AsyncContextFragmentComponent < ApplicationComponent
    attr_reader :src

    def initialize(src:)
      @src = src
    end

    def call
      render(Primer::Alpha::IncludeFragment.new(
        "data-ghost-pilot-context": "",
        "data-src": src,
      ))
    end
  end
end
