# typed: true
# frozen_string_literal: true

module Actions
  class RunnerScaleSets::RunnerScaleSetHeaderDescriptionComponent < ApplicationComponent
    def initialize(scale_set:, owner_settings:)
      @scale_set = scale_set
      @owner_settings = owner_settings
    end

    def runner_group_name
      @scale_set.group_name
    end

    def runner_group_path
      @scale_set.runner_group_path(@owner_settings)
    end
  end
end
