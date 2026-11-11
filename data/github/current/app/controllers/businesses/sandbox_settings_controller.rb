# typed: true
# frozen_string_literal: true

class Businesses::SandboxSettingsController < Businesses::BusinessController
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Businesses::SandboxSettingsController#update",
  ].freeze

  # Valid parameter values accepted by the update action.
  # Note: "all_organizations" is a UI-only value remapped to "all_members" before being persisted.
  VALID_PARAMS = T.let(
    [Configurable::GithubSandboxEnabled::ALL_MEMBERS,
     Configurable::GithubSandboxEnabled::DISABLED,
     "all_organizations"].freeze,
    T::Array[String]
  )

  before_action :business_owner_required
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
    render "businesses/sandbox_settings/index", locals: {
      business: this_business,
    }
  end

  def update
    value = params[:github_sandbox_enabled]

    unless VALID_PARAMS.include?(value)
      flash[:error] = "Select a valid option to continue."
      redirect_to settings_sandboxes_enterprise_path(this_business) and return
    end

    if value == "all_organizations" && !all_orgs_mode_available?
      flash[:error] = "Select a valid option to continue."
      redirect_to settings_sandboxes_enterprise_path(this_business) and return
    end

    all_orgs_mode = value == "all_organizations"
    config_value = all_orgs_mode ? Configurable::GithubSandboxEnabled::ALL_MEMBERS : value
    this_business.update_github_sandbox_enabled(config_value, actor: T.must(current_user))

    # Track the "all orgs" mode separately — this key is Ruby/UI only and not used outside of this application.
    this_business.update_github_sandbox_all_orgs_mode(all_orgs_mode, actor: T.must(current_user))

    if all_orgs_mode
      Businesses::SandboxEnableAllOrgsJob.perform_later(
        business_id: this_business.id,
        actor_id: T.must(current_user).id,
      )
    end

    flash[:notice] = "Sandboxes access policy has been updated."
    redirect_to settings_sandboxes_enterprise_path(this_business)
  end

  private

  def check_sandbox_feature_enabled
    render_404 unless sandbox_feature_enabled?
  end

  def sandbox_feature_enabled?
    GitHub.runtime.dotcom? &&
      this_business.feature_flag_enabled?(:actions_sandboxes_ui, default: false)
  end

  def all_orgs_mode_available?
    this_business.feature_flag_enabled?(:actions_sandboxes_all_orgs_mode_available, default: false)
  end

  # NOTE: A companion flag :actions_sandbox_access_control_enabled exists for
  # enforcing the sandbox-enabled setting for the billable owner.
end
