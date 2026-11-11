# typed: true
# frozen_string_literal: true

class Settings::InstallationsController < ApplicationController
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Settings::InstallationsController#update_permissions",
    "Settings::InstallationsController#update_agent_consent",
  ]

  include IntegrationInstallationsControllerMethods

  # The following actions do not require conditional access checks because
  # they *don't* access any protected organization resources
  # rubocop:disable GitHub/DoNotSkipCapBeforeAction
  skip_before_action :perform_conditional_access_checks, only: %w(
    index
    show
    update
    destroy
    permissions_update_request
    update_permissions
    update_agent_consent
    suspend
    unsuspend
  )

  javascript_bundle :settings
  stylesheet_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Permissions,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    only: [:permissions_update_request, :update_permissions, :update_agent_consent]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Permissions,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Iam,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:permissions_update_request, :update_permissions, :update_agent_consent, :index, :show], optional: true

  private

  def current_context
    current_user
  end
end
