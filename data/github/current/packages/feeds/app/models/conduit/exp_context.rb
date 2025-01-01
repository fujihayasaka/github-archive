# typed: true
# frozen_string_literal: true

module Conduit
  class ExpContext
    include GitHub::Memoizer

    attr_reader :viewer

    def initialize(viewer)
      @viewer = viewer
    end

    memoize def assignment_context
      assignment.assignment_context
    end

    memoize def variants
      assignment.variants
    end

    private

    memoize def assignment
      AzureEXP::Experiments.feeds_assignment(viewer)
    end
  end
end
