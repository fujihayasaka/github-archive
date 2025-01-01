# typed: true
# frozen_string_literal: true

module Actions
  class RunnerScaleSets::RunnerScaleSetLabelsComponent < ApplicationComponent
    def initialize(scale_set:)
      @scale_set = scale_set
      @labels = @scale_set.labels
    end
  end
end
