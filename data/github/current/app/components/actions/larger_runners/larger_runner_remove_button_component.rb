# typed: true
# frozen_string_literal: true

module Actions
  class LargerRunners::LargerRunnerRemoveButtonComponent < ApplicationComponent
    def initialize(larger_runner:, owner_settings:, delete_from_list: false, viewing_from_runner_group: false)
      @larger_runner = larger_runner
      @owner_settings = owner_settings
      @delete_from_list = delete_from_list
      @viewing_from_runner_group = viewing_from_runner_group
    end

    def delete_path
      if @owner_settings.settings_owner_type == "enterprise"
        settings_actions_delete_larger_runner_modal_enterprise_path(@owner_settings.settings_owner.slug, id: @larger_runner.id, viewing_from_runner_group: @viewing_from_runner_group)
      elsif @owner_settings.settings_owner_type == "organization"
        settings_org_actions_delete_larger_runner_modal_path(@owner_settings.settings_owner.display_login, id: @larger_runner.id, viewing_from_runner_group: @viewing_from_runner_group)
      end
    end
  end
end
