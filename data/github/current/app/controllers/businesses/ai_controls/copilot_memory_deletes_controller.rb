# typed: true
# frozen_string_literal: true

class Businesses::AiControls::CopilotMemoryDeletesController < Businesses::BusinessController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include Businesses::CopilotShared
  include Copilot::MemoryAdminDeleteActions

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Businesses::AiControls::CopilotMemoryDeletesController#create",
  ].freeze

  allow_verified_fetch only: [:create]

  before_action :ensure_not_standalone_copilot_business
  before_action :ai_controls_enabled?
  before_action :ai_controls_write_required
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
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot

  private

  sig { override.returns(::Business) }
  def memory_delete_owner
    this_business
  end

  sig { override.returns(String) }
  def memory_delete_status_url
    enterprise_ai_controls_copilot_memory_delete_path(
      this_business,
      memory_delete_target_user_url_options.merge(format: :json)
    )
  end

  sig { void }
  def ai_controls_enabled?
    render_404 unless helpers.show_ai_controls?(this_business)
  end

  sig { void }
  def ai_controls_write_required
    render_404 unless this_business&.actor_can_write_enterprise_ai_controls?(current_user)
  end

  sig { void }
  def memory_deletes_enabled?
    render_404 unless Copilot::MemoryAdminDelete.delete_allowed?(owner: this_business, actor: memory_delete_actor)
  end
end
