# typed: strict
# frozen_string_literal: true

class Orgs::CopilotSettings::RunnerTypeController < Orgs::Controller
  include ApplicationController::VerifiedFetchDependency
  include JsonDependency

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Orgs::CopilotSettings::RunnerTypeController#update",
  ].freeze

  allow_verified_fetch only: [:update]

  before_action :login_required
  before_action :dotcom_required
  before_action :org_admins_only
  before_action :ensure_runner_type_standalone_enabled
  before_action :parse_json_params, only: [:update]

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
    only: [:index, :update]

  sig { returns(String) }
  def self.react_bundle_name
    "copilot-for-business"
  end

  sig { void }
  def index
    if FeatureFlag.vexi.enabled?(:cfb_package_data_router, current_user, default: false)
      respond_with_react(
        payload: IndexPayload.new(payload: index_payload),
        title: Copilot::COPILOT_SWE_AGENT,
        layout: "layouts/settings/copilot_org_react",
        page_data: { selected_link: :organization_copilot_settings_runner_type }
      )
    else
      render_react_app(
        payload: IndexPayload.new(payload: index_payload).payload,
        title: Copilot::COPILOT_SWE_AGENT,
        layout: "layouts/settings/copilot_org_react",
        disable_ssr: true,
        page_data: { selected_link: :organization_copilot_settings_runner_type }
      )
    end
  end

  sig { void }
  def update
    return head :not_found unless request.xhr?

    current_organization.update_copilot_swe_agent_runner(
      runner_type: params[:runner_type],
      runner_labels: params[:runner_labels] || "",
      runner_group_name: params[:runner_group_name] || "",
      allow_repo_custom_runner: params[:allow_repo_custom_runner].nil? ? nil : ActiveModel::Type::Boolean.new.cast(params[:allow_repo_custom_runner]),
      actor: current_user,
    )

    head :ok
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    Failbot.report(e)
    head :unprocessable_entity
  end

  private

  sig { void }
  def ensure_runner_type_standalone_enabled
    head :not_found unless runner_type_standalone_enabled? && (coding_agent_visible? || copilot_code_review_enabled?)
  end

  sig { returns(T::Boolean) }
  def runner_type_standalone_enabled?
    FeatureFlag.vexi.enabled?(:ccr_runner_type_org_settings, current_organization, default: false) &&
      FeatureFlag.vexi.enabled?(:copilot_swe_agent_runner_control_settings, current_organization, default: false)
  end

  sig { returns(T::Boolean) }
  def coding_agent_visible?
    !(GitHub.multi_tenant_enterprise? && !FeatureFlag.vexi.enabled?(:coding_agent_in_proxima, current_organization, default: false))
  end

  sig { returns(T::Boolean) }
  def copilot_code_review_enabled?
    copilot_org = ::Copilot::Organization.new(current_organization)
    copilot_org.code_review_enabled?
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def index_payload
    {
      project_display_name: Copilot::COPILOT_SWE_AGENT.to_s,
      org_login: current_organization.display_login.to_s,
      runner_type: current_organization.copilot_swe_agent_runner_type.to_s,
      runner_labels: current_organization.copilot_swe_agent_runner_labels.to_s,
      runner_group_name: current_organization.copilot_swe_agent_runner_group_name.to_s,
      allow_repo_custom_runner: !!current_organization.copilot_swe_agent_allow_repo_custom_runner,
      runner_settings_changed_callback_path: settings_org_copilot_runner_type_update_path.to_s,
    }
  end

  class IndexPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "copilotForBusinessRunnerTypeRoute"
    end

    sig { params(payload: T::Hash[Symbol, T.untyped]).void }
    def initialize(payload:)
      @payload = payload
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def payload
      @payload
    end
  end
end
