# typed: true
# frozen_string_literal: true

module Actions
  class RunnerGroupRemoveButtonComponent < ApplicationComponent
    def initialize(runner_group:, owner_settings:, delete_from_list: false)
      @runner_group = runner_group
      @owner_settings = owner_settings
      @delete_from_list = delete_from_list
    end

    def should_block_remove?
      @runner_group.runners.length > 0
    end

    def delete_runner_group_path
      @owner_settings.delete_runner_group_path(id: @runner_group.id)
    end
  end
end
