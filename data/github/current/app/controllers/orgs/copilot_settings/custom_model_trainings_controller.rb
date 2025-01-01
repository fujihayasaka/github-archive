# typed: strict
# frozen_string_literal: true

class Orgs::CopilotSettings::CustomModelTrainingsController < Orgs::CopilotSettings::BaseController
  extend GitHub::Memoizer

  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include ReactHelper
  include Orca::OrcaControllerHelper

  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:show]

  before_action :check_copilot_available
  before_action :feature_required
  before_action :check_pipeline_access, only: [:show]

  javascript_bundle :settings
  javascript_bundle :copilot

  sig { returns(String) }
  def self.react_bundle_name
    "copilot-custom-models"
  end

  sig { void }
  def show
    payload = pipeline_details_as_json(T.must(current_pipeline))
    pipeline_id = T.must(current_pipeline).pipeline_id
    react_payload = {
      adminEmail: admin_email,
      editPath: edit_path(pipeline_id),
      enabled_features: feature_flags,
      hasAnyDeployed: any_deployed?,
      indexPath: index_path,
      isStale: stale?,
      organization: {
        slug: current_organization.display_login,
      },
      pipelineDetails: payload,
      rateLimitResetAt: rate_limit_reset_at,
      withinRateLimit: within_rate_limit?,
    }

    render_react_app(
      layout: "layouts/copilot/custom_models",
      title: "GitHub Copilot - Custom model",
      payload: react_payload,
      ssr: true
    )
  end

  private

  sig { returns(T::Boolean) }
  def stale?
    deployed = latest_completed_pipeline

    return false if deployed.nil?

    current = T.must(current_pipeline)
    return false if deployed.created_at.blank?
    return false if current.created_at.blank?

    deployed.created_at > current.created_at
  end
end
