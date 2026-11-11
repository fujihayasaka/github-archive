# typed: strict
# frozen_string_literal: true

class Businesses::AiControls::McpController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Businesses::CopilotShared
  include Businesses::AiControls::McpAllowlistFeatureFlag
  include Businesses::AiControls::McpPrivateServersFeatureFlag

  javascript_bundle :copilot

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot

  layout "layouts/react_business"

  allow_verified_fetch only: [:index]

  before_action :ensure_not_standalone_copilot_business
  before_action :ai_controls_enabled?
  before_action :ensure_trial_business_is_dfd_trial_or_contains_cfb_trial, only: [:index]
  before_action :handle_ai_controls_trial_entry_flow, only: [:index]
  before_action :ai_controls_read_required

  rescue_from StandardError, with: :handle_unexpected_error

  sig { void }
  def index
    render "businesses/ai_controls/mcp/index", locals: {
      business: this_business,
      copilot_business: copilot_business,
      can_write: this_business&.actor_can_write_enterprise_ai_controls?(current_user) || false,
      is_admin: this_business&.adminable_by?(current_user) || false,
      title: "MCP",
      allowlist_ui_enabled: allowlist_feature_flag_enabled?,
      private_servers_ui_enabled: private_servers_feature_flag_enabled?,
    }
  end

  private

  sig { override.returns(String) }
  def ai_controls_section_title
    "MCP"
  end

  sig { override.returns(Symbol) }
  def ai_controls_selected_link
    :businesses_ai_controls_mcp
  end

  sig { void }
  def ai_controls_enabled?
    render_404 unless helpers.show_ai_controls?(this_business)
  end

  sig { void }
  def ai_controls_read_required
    render_404 unless this_business&.actor_can_read_enterprise_ai_controls?(current_user)
  end

  sig { params(error: StandardError).void }
  def handle_unexpected_error(error)
    logger.error("MCP_Registry_Enterprise_Error: MCP page error for business #{this_business&.id}: #{error.class}: #{error.message}\n#{error.backtrace&.first(10)&.join("\n")}")
    raise
  end
end
