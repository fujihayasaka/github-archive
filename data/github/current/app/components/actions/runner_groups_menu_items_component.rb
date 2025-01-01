# typed: true
# frozen_string_literal: true

module Actions
  class RunnerGroupsMenuItemsComponent < ApplicationComponent

    def initialize(owner:, owner_settings:, runner_groups:)
      @owner = owner
      @owner_settings = owner_settings
      @runner_groups = runner_groups.reject(&:inherited?).sort
    end
  end
end
