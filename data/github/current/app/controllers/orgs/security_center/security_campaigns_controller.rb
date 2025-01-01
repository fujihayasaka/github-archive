# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::SecurityCampaignsController < Orgs::SecurityCenter::AbstractSecurityCampaignsController
  include CodeScanningHelper
  include ApplicationHelper
  include ReactHelper
  include ScanningHelper
  include SecurityCampaigns::AlertResultsHelper
  include SecurityCampaigns::CampaignsSerializer
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :manage_security_products_permission_required, except: [:show]
  before_action :organization_read_required, only: [:show]

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "Orgs::SecurityCenter::SecurityCampaignsController#create"
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
    ApplicationRecord::Iam,
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
    return render status: 422, json: { message: "Campaign manager must be a security manager of this organization" } unless SecurityCampaigns.potential_campaign_managers(org: this_organization).include?(manager)

    ends_at = Time.zone.parse(params[:campaign_due_date])
    return render status: 400, json: { message: "Invalid due date" } if ends_at.blank? || ends_at < Time.zone.now

    return render status: 422, json: { message: "Invalid query" } if !query.is_valid?

    org_campaigns_count = SecurityCampaigns::SecurityCampaign.open.where(organization_id: this_organization.id).count
    return render status: 400, json: { message: SecurityCampaigns::MAX_CAMPAIGNS_CREATION_ERROR_MESSAGE } if org_campaigns_count >= SecurityCampaigns::MAX_CAMPAIGNS_COUNT

    alert_results, has_error = alert_results_from_query(query)
    return render status: 500, json: { message: "Failed to fetch alerts to include in the campaign. Please reload and try again." } if has_error

    return render status: 422, json: { message: "Could not find any alerts to include in the campaign. Please reload and try again." } if alert_results.empty?

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
    rescue ActiveRecord::RecordInvalid => e
      if e.record.errors.any? { |r| r.type == :rate_limited }
        # unable to use 429 as that status code results in a re-direct to a 429 status page
        return render status: 403, json: { message: "Too many campaigns are being created in this organization at this moment. Please try again later." }
      else
        return render status: 422, json: { message: e.message }
      end
    end

    SecurityCampaigns::CreateSecurityCampaignAlertsJob.perform_later(
      security_campaign_id: T.must(campaign.id),
      query_string:,
      user_id: T.must(current_user&.id),
      organization_id: this_organization.id,
      user_session_id: user_session.id,
    ) if T.must(current_user).feature_enabled?(:security_campaigns_write_without_alerts_limit) && this_organization.feature_enabled?(:security_campaigns_write_without_alerts_limit)

    render status: 200, json: {
      message: "Campaign created successfully",
      campaignPath: security_center_security_campaign_path(number: T.must(campaign).number),
    }
  end

  def show
    campaign = find_security_campaign(number: params[:number])
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
      codeScanningRepoListPath: security_center_code_scanning_repository_list_path(this_organization, format: :json),
      codeScanningToolListPath: security_center_code_scanning_tool_list_path(this_organization, format: :json),
      codeScanningRuleListPath: security_center_code_scanning_rule_list_path(this_organization, format: :json),
      codeScanningTagListPath: security_center_code_scanning_tag_list_path(this_organization, format: :json),
      closedCampaignsPath: security_center_closed_security_campaigns_path(org: this_organization),
      showAutofixGeneratedFilter: user.feature_enabled?(:autofix_alert_filter),
      showCampaignManagementActions: can_manage_security_products?,
    }

    data = log_timing(step: "build layout data") do
      {
        backfill_in_progress: this_organization.trigger_security_center_reconciliation,
        selected_tab: campaign.closed? ? :security_campaign_closed_campaigns : "security_campaign_#{campaign.number}".to_sym,
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
    return render status: 422, json: { message: "Campaign manager must be a security manager of this organization" } unless SecurityCampaigns.potential_campaign_managers(org: this_organization).include?(manager)

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

    SecurityCampaigns::DeletionService.call(campaign: campaign, actor: T.must(current_user))

    flash[:notice] = "The campaign \"#{campaign.name}\" was successfully deleted."

    render status: 200, json: { message: "Campaign deleted successfully" }
  end
end
