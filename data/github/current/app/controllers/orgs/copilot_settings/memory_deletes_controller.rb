# typed: true
# frozen_string_literal: true

class Orgs::CopilotSettings::MemoryDeletesController < Orgs::Controller
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include Copilot::MemoryAdminDeleteActions
  include Orgs::CopilotSettings::SeatManagementDependency

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Orgs::CopilotSettings::MemoryDeletesController#create",
  ].freeze

  allow_verified_fetch only: [:create]

  before_action :dotcom_required
  before_action :org_admins_only
  before_action :check_not_legacy_plan
  before_action :check_copilot_available
  before_action :memory_deletes_enabled?
  before_action :resolve_memory_delete_target_user

  rate_limit_requests \
    only: [:create],
    if: :creating_new_memory_delete?,
    key: :memory_delete_rate_limit_key,
    max: Copilot::MemoryAdminDeleteActions::CREATE_RATE_LIMIT_MAX,
    ttl: Copilot::MemoryAdminDeleteActions::CREATE_RATE_LIMIT_TTL,
    at_limit: :memory_delete_rate_limited,
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
  def memory_delete_owner
    current_organization
  end

  sig { override.returns(String) }
  def memory_delete_status_url
    settings_org_copilot_memory_delete_path(
      current_organization,
      memory_delete_target_user_url_options.merge(format: :json)
    )
  end

  sig { void }
  def memory_deletes_enabled?
    render_404 unless Copilot::MemoryAdminDelete.delete_allowed?(owner: current_organization, actor: memory_delete_actor)
  end
end
