# typed: true
# frozen_string_literal: true

module Actions
  class RunnerRemoveButtonComponent < ApplicationComponent
    def initialize(runner_id:, os:, owner_settings:, delete_from_list: false)
      @runner_id = runner_id
      @owner_settings = owner_settings
      @delete_from_list = delete_from_list
      @os = os
    end

    def delete_path
      @owner_settings.delete_runner_path(id: @runner_id, os: @os)
    end
  end
end
