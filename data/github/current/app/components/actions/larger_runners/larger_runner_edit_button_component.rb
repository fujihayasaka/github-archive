# typed: strict
# frozen_string_literal: true

module Actions
  class LargerRunners::LargerRunnerEditButtonComponent < ApplicationComponent
    sig do
      params(
        larger_runner: Actions::LargerRunner,
        owner_settings: T.any(Actions::OrgRunnersView, Actions::EnterpriseRunnersView),
        edit_from_list: T.nilable(T::Boolean),
        viewing_from_runner_group: T.nilable(T::Boolean),
        viewing_from_details: T.nilable(T::Boolean)
      ).void
    end
    def initialize(
      larger_runner:,
      owner_settings:,
      edit_from_list: false,
      viewing_from_runner_group: false,
      viewing_from_details: false
    )
      @larger_runner = larger_runner
      @owner_settings = owner_settings
      @edit_from_list = edit_from_list
      @viewing_from_runner_group = viewing_from_runner_group
      @viewing_from_details = viewing_from_details
    end

    sig { returns(T.nilable(String)) }
    def edit_path
      if @owner_settings.settings_owner_type == "enterprise"
        settings_actions_edit_larger_runner_enterprise_path(
          @owner_settings.settings_owner.slug,
          id: @larger_runner.id,
          viewing_from_runner_group: @viewing_from_runner_group,
          viewing_from_details: @viewing_from_details
        )
      elsif @owner_settings.settings_owner_type == "organization"
        settings_org_actions_edit_larger_runner_path(
          @owner_settings.settings_owner.display_login,
          id: @larger_runner.id,
          viewing_from_runner_group: @viewing_from_runner_group,
          viewing_from_details: @viewing_from_details
        )
      end
    end
  end
end
