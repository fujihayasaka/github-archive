# typed: true
# frozen_string_literal: true

module Actions
  class RunnerScaleSets::RunnerScaleSetComponent < ApplicationComponent
    def initialize(scale_set:)
      @scale_set = scale_set
    end
  end
end
