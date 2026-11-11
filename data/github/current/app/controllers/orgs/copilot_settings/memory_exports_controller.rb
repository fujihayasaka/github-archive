# typed: true
# frozen_string_literal: true

class Orgs::CopilotSettings::MemoryExportsController < Orgs::Controller
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Copilot::MemoryAdminExportsActions
  include Orgs::CopilotSettings::SeatManagementDependency

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Orgs::CopilotSettings::MemoryExportsController#create",
  ].freeze

  allow_verified_fetch only: [:create]

  before_action :dotcom_required
  before_action :org_admins_only
  before_action :check_not_legacy_plan
  before_action :check_copilot_available
  before_action :memory_exports_enabled?
  before_action :resolve_memory_export_target_user

  rate_limit_requests \
    only: [:create],
    if: :creating_new_memory_export?,
    key: :memory_export_rate_limit_key,
    max: Copilot::MemoryAdminExportsActions::TARGET_USER_EXPORT_RATE_LIMIT_MAX,
    ttl: Copilot::MemoryAdminExportsActions::TARGET_USER_EXPORT_RATE_LIMIT_TTL,
    at_limit: :memory_export_rate_limited,
    render_allow_body: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Authnd

  private

  sig { override.returns(::Organization) }
  def memory_export_owner
    current_organization
  end

  sig { override.returns(String) }
  def memory_export_download_url
    download_settings_org_copilot_memory_export_path(current_organization, memory_export_target_user_url_options)
  end

  sig { override.returns(String) }
  def memory_export_status_url
    settings_org_copilot_memory_export_path(
      current_organization,
      memory_export_target_user_url_options.merge(format: :json)
    )
  end

  sig { void }
  def memory_exports_enabled?
    render_404 unless Copilot::MemoryAdminExport.export_allowed?(owner: current_organization, actor: memory_export_actor)
  end
end
