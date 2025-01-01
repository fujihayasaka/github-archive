# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::SecurityCampaignsPublishController < Orgs::SecurityCenter::AbstractSecurityCampaignsController
  include SecurityCampaigns::CampaignsSerializer
  include Orgs::SecurityCenter::CodeScanningOrgQueriesHelper

  before_action :manage_security_products_permission_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Notify,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Spokes,
    only: [:show]

  depends_on_clusters \
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::SecurityOverviewAnalytics,
    only: [:show],
    optional: true

  def show
    query_params = params[:query]
    return render status: 422, json: { message: "Query should be defined" } unless query_params.present?
    return render status: 422, json: { message: "Invalid query" } if !query.is_valid?

    data = log_timing(step: "build layout data") do
      {
        backfill_in_progress: this_organization.trigger_security_center_reconciliation,
        selected_tab: :campaigns,
      }
    end

    payload = {
      organizationLogin: this_organization.display_login,
      currentUser: serialized_campaign_user(user: current_user),
      maxManagers: SecurityCampaigns::MAX_MANAGER_COUNT,
      creationQuery: query_params,
      campaignName: params[:campaign_name],
      campaignDescription: params[:campaign_description],
      sourceCampaignNumber: params[:source_campaign_number]&.to_i,
      orgOpenCampaignsCount: SecurityCampaigns::SecurityCampaign.open.where(organization_id: this_organization.id).count,
      maxOpenCampaigns: SecurityCampaigns::MAX_OPEN_CAMPAIGNS_COUNT,

      showGenerateIssues: SecurityCampaigns.issue_creation_enabled?(this_organization) && !current_user.spammy?
    }

    render_react_app(
      app_name: "security-campaigns",
      payload:,
      title: "Security · Publish campaign",
      layout: "layouts/security_center/with_sidebar",
      page_data: { data: },
      disable_ssr: true
    )
  end
end
