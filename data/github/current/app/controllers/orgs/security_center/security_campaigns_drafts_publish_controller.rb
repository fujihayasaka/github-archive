# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::SecurityCampaignsDraftsPublishController < Orgs::SecurityCenter::AbstractSecurityCampaignsController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include SecurityCampaigns::CampaignsSerializer
  include SecurityCampaigns::OpeningConcern

  before_action :manage_security_products_permission_required

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "Orgs::SecurityCenter::SecurityCampaignsDraftsPublishController#create"
  ].freeze, T::Array[String])

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
    only: [:show, :create]

  depends_on_clusters \
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::SecurityOverviewAnalytics,
    only: [:show, :create],
    optional: true

  allow_verified_fetch only: [:create]
  before_action :try_parse_json_params, only: [:create]

  def show
    return render_404 if !SecurityCampaigns.drafts_enabled?(current_user)

    campaign_number = params[:number].to_i
    campaign = SecurityCampaigns::SecurityCampaign.
      includes(:user_manager_users, team_manager_teams: :organization).
      draft.
      find_by(number: campaign_number, organization: this_organization.id)
    return render_404 if campaign.nil?

    data = log_timing(step: "build layout data") do
      {
        backfill_in_progress: this_organization.trigger_security_center_reconciliation,
        selected_tab: :campaigns,
      }
    end

    payload = {
      campaign: serialized_campaign(security_campaign: campaign, owner_display_login: this_organization.display_login, current_user:),
      organizationLogin: this_organization.display_login,
      currentUser: serialized_campaign_user(user: current_user),
      maxManagers: SecurityCampaigns::MAX_MANAGER_COUNT,
      orgOpenCampaignsCount: SecurityCampaigns::SecurityCampaign.open.where(organization_id: this_organization.id).count,
      maxOpenCampaigns: SecurityCampaigns::MAX_OPEN_CAMPAIGNS_COUNT,

      showAutofixPullRequests: SecurityCampaigns.autofix_pr_creation_enabled?(this_organization),
      showGenerateIssues: SecurityCampaigns.issue_creation_enabled?(this_organization),
    }

    render_react_app(
      app_name: "security-campaigns",
      payload:,
      title: "Security · Publish #{campaign.name}",
      layout: "layouts/security_center/with_sidebar",
      page_data: { data: },
      disable_ssr: true
    )
  end

  def create
    return render_404 if !SecurityCampaigns.drafts_enabled?(current_user)

    campaign_number = params[:number].to_i
    campaign = SecurityCampaigns::SecurityCampaign.
      includes(:user_manager_users, team_manager_teams: :organization).
      draft.
      find_by(number: campaign_number, organization: this_organization.id)
    return render_404 if campaign.nil?

    opening_details = campaign_opening_details_from_params(this_organization, current_user)
    return opening_details if opening_details.is_a?(String)

    org_campaigns_count = SecurityCampaigns::SecurityCampaign.open.where(organization_id: this_organization.id).count
    return render status: 400, json: { message: SecurityCampaigns::MAX_OPEN_CAMPAIGNS_PUBLISH_ERROR_MESSAGE } if org_campaigns_count >= SecurityCampaigns::MAX_OPEN_CAMPAIGNS_COUNT

    campaign = begin
      SecurityCampaigns::PublishingService.call(
        campaign: campaign,
        opening_details: opening_details,
        actor: T.must(current_user)
      )
    rescue ActiveRecord::RecordNotSaved => e
      return render status: 400, json: { message: e.message }
    rescue ActiveRecord::RecordInvalid => e
      if e.record.errors.any? { |r| r.type == :rate_limited }
        # unable to use 429 as that status code results in a re-direct to a 429 status page
        return render status: 403, json: { message: "Too many campaigns are being published in this organization at this moment. Please try again later." }
      else
        return render status: 422, json: { message: e.message }
      end
    rescue SecurityCampaigns::TurboscanError => e
      return render status: 500, json: { message: "An error occurred while publishing the security campaign, please try again later." }
    end

    flash[:notice] = campaign_open_flash_message(opening_details, "published")

    render status: 200, json: {
      campaignNumber: campaign_number,
    }
  end
end
