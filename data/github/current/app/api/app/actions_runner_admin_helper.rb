# typed: true
# frozen_string_literal: true

require "github-launch"
require "github/launch_client"

module Api::App::ActionsRunnerAdminHelper
  sig { params(owner: T.any(Organization, Business, Repository, User), is_ui_read: T::Boolean, is_api_read: T::Boolean, is_write: T::Boolean).returns(T::Boolean) }
  public def use_runner_admin?(owner, is_ui_read: false, is_api_read: false, is_write: false)
    return true if owner.feature_flag_enabled?(:actions_runners_use_runner_admin_service, default: false)

    owner.feature_flag_enabled?(:actions_runners_attempt_runner_admin, default: false)
  end
end
