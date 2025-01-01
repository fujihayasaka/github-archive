# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::SecurityCampaignsController < Orgs::SecurityCenter::AbstractSecurityCampaignsController
  extend T::Sig
  include CodeScanningHelper
  include ApplicationHelper
  include ReactHelper
  include ScanningHelper
  include SecurityCampaigns::AlertResultsHelper
  include SecurityCampaigns::CampaignsSerializer
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "Orgs::SecurityCenter::SecurityCampaignsController#create"
  ].freeze, T::Array[String])

  before_action :security_campaigns_creation_required, only: [:create]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Notify,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    only: [:create]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Notify,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    only: [:show]

  depends_on_clusters \
    ApplicationRecord::Copilot,
    ApplicationRecord::SecurityOverviewAnalytics,
    only: [:create, :show],
    optional: true

  allow_verified_fetch only: [:create, :update, :destroy]
  before_action :try_parse_json_params, only: [:create, :update]

  def create
    return render status: 422, json: { message: "Campaign name required" } if params[:campaign_name].blank?
    return render status: 422, json: { message: "Campaign description required" } if params[:campaign_description].blank?
    return render status: 422, json: { message: "Campaign due date required" } if params[:campaign_due_date].blank?
    return render status: 422, json: { message: "Campaign manager required" } if params[:campaign_manager].blank?

    manager = User.find_by(id: params[:campaign_manager])
    return render status: 404, json: { message: "Campaign manager not found" } unless manager

    ends_at = Time.zone.parse(params[:campaign_due_date])
    return render status: 400, json: { message: "Invalid due date" } if ends_at.blank? || ends_at < Time.zone.now

    return render status: 422, json: { message: "Invalid query" } if !query.is_valid?

    org_campaigns_count = SecurityCampaigns::SecurityCampaign.open.where(organization_id: this_organization.id).count
    return render status: 400, json: { message: SecurityCampaigns::MAX_CAMPAIGNS_ERROR_MESSAGE } if org_campaigns_count >= SecurityCampaigns::MAX_CAMPAIGNS_COUNT

    alert_results, has_error = alert_results_from_query(query)
    return render status: 500, json: { message: "Error fetching alerts" } if has_error

    return render status: 422, json: { message: "No alerts found" } if alert_results.empty?

    alerts = security_campaigns_alerts_from_alert_results(alert_results)

    campaign = begin
      new_campaign = SecurityCampaigns::SecurityCampaign.new(
        organization: this_organization,
        name: params[:campaign_name],
        manager:,
        description: params[:campaign_description],
        ends_at:,
      )
      SecurityCampaigns::CreationService.call(campaign: new_campaign, logical_alert_info: alerts, actor: T.must(current_user), query_string:)
    rescue ActiveRecord::RecordNotSaved => e
      return render status: 400, json: { message: e.message }
    end

    SecurityCampaigns::GenerateAutofixesService.call(this_organization, alerts)

    render status: 200, json: {
      message: "Campaign created successfully",
      campaignPath: security_center_security_campaign_path(number: T.must(campaign).number),
    }
  end

  def show
    campaign = SecurityCampaigns::SecurityCampaign.find_by(number: params[:number], organization: this_organization.id)
    return render_404 if campaign.nil?
    user = current_user
    return render_404 if user.nil?

    payload = {
      campaign: serialized_campaign(security_campaign: campaign, owner_display_login: this_organization.display_login),
      alertsPath: security_center_security_campaign_alerts_path(this_organization),
      alertsGroupsPath: security_center_security_campaign_alerts_groups_path(this_organization),
      campaignManagersPath: security_center_security_campaigns_managers_path(this_organization),
      securityOverviewPath: security_center_overview_dashboard_path(this_organization),
      suggestionsPath: security_center_options_path(this_organization),
      isAlertsGroupsEnabled: GitHub.flipper[:security_campaigns_alerts_groups].enabled?(user),
      isClosedCampaignsFeatureEnabled: user.feature_enabled?(:security_campaigns_closed),
    }

    data = log_timing(step: "build layout data") do
      {
        backfill_in_progress: this_organization.trigger_security_center_reconciliation,
        selected_tab: "security_campaign_#{campaign.number}".to_sym,
      }
    end

    render_react_app(
      app_name: "security-campaigns",
      payload:,
      title: campaign.name + " · Security Campaign",
      layout: "layouts/security_center/with_sidebar",
      page_data: { data: },
      ssr: false
    )
  end

  def update
    campaign = SecurityCampaigns::SecurityCampaign.find_by(number: params[:number], organization: this_organization.id)
    return render_404 if campaign.nil?

    return render status: 422, json: { message: "Closed campaigns cannot be updated" } if campaign.closed?
    return render status: 422, json: { message: "Campaign name required" } if params[:campaign_name].blank?
    return render status: 422, json: { message: "Campaign description required" } if params[:campaign_description].blank?
    return render status: 422, json: { message: "Campaign due date required" } if params[:campaign_due_date].blank?
    return render status: 422, json: { message: "Campaign manager required" } if params[:campaign_manager].blank?

    manager = User.find_by(id: params[:campaign_manager])
    return render status: 404, json: { message: "Campaign manager not found" } unless manager

    ends_at = Time.zone.parse(params[:campaign_due_date])
    return render status: 400, json: { message: "Invalid due date" } if ends_at.blank?

    campaign.update!(
      name: params[:campaign_name],
      description: params[:campaign_description],
      ends_at: ends_at,
      manager: manager,
    )

    render status: 200, json: { message: "Campaign updated successfully" }
  end

  def destroy
    campaign = SecurityCampaigns::SecurityCampaign.find_by(number: params[:number], organization: this_organization.id)
    return render_404 if campaign.nil?

    SecurityCampaigns::SecurityCampaignRepository.where(security_campaign_id: campaign.id).in_batches(of: 10) do |batch|
      SecurityCampaigns::SecurityCampaignRepository.throttle do
        batch.delete_all
      end
    end

    SecurityCampaigns::SecurityCampaignAlert.where(security_campaign_id: campaign.id).in_batches(of: 10) do |batch|
      SecurityCampaigns::SecurityCampaignAlert.throttle do
        batch.delete_all
      end
    end

    campaign.destroy!

    GlobalInstrumenter.instrument("security_campaigns.security_campaign_delete", {
      actor: current_user,
      security_campaign: campaign,
    })

    render status: 200, json: { message: "Campaign deleted successfully" }
  end

  private

  def security_campaigns_creation_required
    render_404 unless SecurityCampaigns.creation_enabled?(this_organization)
  end
end
