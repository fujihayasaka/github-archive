# typed: strict
# frozen_string_literal: true

class Organizations::Settings::CodeQualityController < Orgs::Controller
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:update]

  before_action :login_required
  before_action :ensure_code_quality_org_settings_feature_enabled
  before_action :manage_security_products_permission_required
  before_action :try_parse_json_params, only: [:update]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    only: [:index]

  class IndexPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "orgCodeQualitySettingsRoute"
    end

    sig { params(org: Organization, enabled: T::Boolean).void }
    def initialize(org:, enabled:)
      @org = org
      @enabled = enabled
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      # We exclude archived repos (also ignored in the bulk enablement job) to avoid artificially inflating the number of repos
      { org: @org.display_login, orgName: @org.safe_profile_name, enabled: @enabled, repoCount: @org.repositories.active.not_archived_scope.count }
    end
  end

  sig { void }
  def index
    respond_with_react(
      payload: IndexPayload.new(org: current_organization, enabled: current_organization.code_quality_enabled_on_new_repos?),
      app_name: "code-quality",
      title: "Settings · Code quality · #{current_organization.safe_profile_name}",
      page_data: { selected_link: :settings_org_code_quality },
      layout: "organization_settings",
    )
  end

  sig { void }
  def update
    unless [true, false].include?(params[:enabled])
      render json: { error: "Missing or invalid 'enabled' parameter" }, status: :unprocessable_entity
      return
    end

    begin
      if params[:enabled]
        current_organization.enable_code_quality_on_new_repos(actor: current_user)
      else
        current_organization.disable_code_quality_on_new_repos(actor: current_user)
      end
    rescue Configurable::CodeQualityNewRepos::ConfigurationError => e
      render json: { error: e.message }, status: :unprocessable_entity
      return
    end

    CodeQualityBulkEnablementJob.perform_later(
      organization_id: current_organization.id,
      actor_id: current_user.id,
      enabled: params[:enabled],
    )

    CodeQualityEnablement.increment_enablement(
      metric: "request",
      tags: ["source:bulk_org", "enabled:#{params[:enabled]}"],
    )

    render json: { enabled: params[:enabled] }, status: :ok
  end

  private

  sig { void }
  def ensure_code_quality_org_settings_feature_enabled
    render_404 unless FeatureFlag.vexi.enabled?(
      :code_quality_org_settings, current_organization, default: false
    )
  end
end
