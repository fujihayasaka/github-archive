# typed: true
# frozen_string_literal: true

class Orgs::CopilotSettings::ContentExclusionController < Orgs::Controller
  extend T::Sig

  include GitHub::Memoizer
  include ReactHelper
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  allow_verified_fetch only: [:update]

  before_action :dotcom_required
  before_action :org_admins_only

  before_action :check_if_billable
  before_action :feature_required
  before_action :parse_json_params, only: [:update]

  javascript_bundle :settings
  javascript_bundle :copilot

  depends_on_clusters \
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:show]

  def self.react_bundle_name
    "copilot-content-exclusion"
  end

  def show
    config = Copilot::ContentExclusionConfiguration.for_organization(current_organization).first
    render_react_app(
      payload: {
        organization: current_organization.display_login,
        lastEdited: config&.updated_by ? { login: config.updated_by.display_login, time: config.updated_at, link: audit_log_link } : nil,
        document: config&.document
      },
      title: "Copilot content exclusion",
      page_data: {
        selected_link: :org_settings_copilot_content_exclusion
      },
      layout: "organization_settings",
      ssr: true
    )
  end

  sig { void }
  def update
    content_exclusion_config = Copilot::ContentExclusionConfiguration.for_organization(current_organization).first
    new_paths = params[:paths]

    if content_exclusion_config.present?
      GitHub.logger.info("Updating ContentExclusionConfiguration", "gh.org.id" => current_organization.id, "gh.copilot_ignore_config.id" => content_exclusion_config.id)
      content_exclusion_config.update(
        document: new_paths,
        updated_by: current_user,
      )
    else
      GitHub.logger.info("Creating ContentExclusionConfiguration", "gh.org.id" => current_organization.id)
      content_exclusion_config = Copilot::ContentExclusionConfiguration.create(
        resource: current_organization,
        updated_by: current_user,
        resource_type: "Organization",
        document: new_paths
      )
    end

    if content_exclusion_config.valid?

      payload = {
        message: "Successfully updated the excluded paths",
        lastEdited: {
          login: current_user&.display_login,
          time: content_exclusion_config.updated_at,
          link: audit_log_link
        }
      }

      render json: payload
    else
      render json: { message: content_exclusion_config.errors.first.message }, status: :unprocessable_entity
    end
  end

  private

  sig { returns Copilot::Organization }
  memoize def copilot_organization
    T.must_because(current_copilot_organization) { "#org_admins_only ensures non-nil" }
  end

  def check_if_billable
    redirect_to settings_org_copilot_seat_management_path(current_organization) unless copilot_organization.copilot_billable? || copilot_organization.on_free_trial?
  end

  def feature_required
    render_404 unless Copilot::ContentExclusion.is_available?(current_organization)
  end

  def audit_log_link
    query = Search::Queries::AuditLogQuery.stringify(["action:#{Copilot::Events::COPILOT_FOR_BUSINESS_CONTENT_EXCLUSION_CHANGED}"])
    settings_org_audit_log_path(current_organization, q: query)
  end
end
