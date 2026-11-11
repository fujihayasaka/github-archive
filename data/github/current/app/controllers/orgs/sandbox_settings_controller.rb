# typed: true
# frozen_string_literal: true

class Orgs::SandboxSettingsController < Orgs::Controller
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Orgs::SandboxSettingsController#update",
  ].freeze

  before_action :dotcom_required
  before_action :org_admins_only
  before_action :check_sandbox_feature_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    only: [:index, :update]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    render "settings/organization/sandboxes/index"
  end

  def update
    value = params[:github_sandbox_enabled]

    unless Configurable::GithubSandboxEnabled::CONFIG_TYPES.include?(value)
      flash[:error] = "Invalid sandbox access setting."
      redirect_to action: "index" and return
    end

    current_organization.update_github_sandbox_enabled(value, actor: T.must(current_user))

    flash[:notice] = "Sandboxes access updated."
    redirect_to action: "index"
  end

  private

  def check_sandbox_feature_enabled
    render_404 unless sandbox_feature_enabled?
  end

  def sandbox_feature_enabled?
    # If parent enterprise flag is enabled, also check the parent enterprise flag
    # so orgs automatically get access when the enterprise flag is toggled
    current_organization.feature_flag_enabled?(:actions_sandboxes_ui, default: false) ||
      current_organization.business&.feature_flag_enabled?(:actions_sandboxes_ui, default: false) || false
  end

  # NOTE: A companion flag :actions_sandbox_access_control_enabled exists for
  # use in the launch service. When enabled, it enforces the sandbox-enabled UI
  # setting for the billable owner.
end
