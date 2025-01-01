# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::SecurityCampaignsController < Orgs::SecurityCenter::AbstractSecurityCampaignsController
  include CodeScanningHelper
  include ApplicationHelper
  include ScanningHelper
  include SecurityCampaigns::AlertResultsHelper
  include SecurityCampaigns::CampaignsSerializer
  include SecurityCampaigns::ManagersDependency
  include SecurityCampaigns::OpeningConcern
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :manage_security_products_permission_required, except: [:index, :show]
  before_action :organization_read_required, only: [:index, :show]

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "Orgs::SecurityCenter::SecurityCampaignsController#create",
    "Orgs::SecurityCenter::SecurityCampaignsController#update",
    "Orgs::SecurityCenter::SecurityCampaignsController#destroy",

  ].freeze, T::Array[String])

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Notify,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
  only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Notify,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Notify,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Spokes,
    only: [:create, :update]

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
    only: [:destroy]

  depends_on_clusters \
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::SecurityOverviewAnalytics,
    only: [:index, :new, :create, :show, :update, :destroy],
    optional: true

  allow_verified_fetch only: [:create, :update, :destroy]
  before_action :try_parse_json_params, only: [:create, :update]

  def index
    return render_404 if !SecurityCampaigns.enabled?(this_organization) || !SecurityCampaigns.campaigns_ga_enabled?(current_user)

    data = log_timing(step: "build layout data") do
      {
        backfill_in_progress: this_organization.trigger_security_center_reconciliation,
        selected_tab: :campaigns,
      }
    end

    can_manage_security_products = SecurityProduct::Permissions::OrgAuthz.new(this_organization, actor: current_user).can_manage_security_products?

    visible_campaign_counts = SecurityCampaigns::VisibleCampaignsCountsService.call(
      user: current_user,
      org: this_organization,
      allowed_repository_ids: allowed_repo_ids_and_limit_exceeded&.first,
      can_manage_security_products:
    )
    security_campaigns_draft_enabled = SecurityCampaigns.drafts_enabled?(current_user)
    templates = SecurityCampaigns::CampaignTemplates::ALL_TEMPLATES.map do |id, template|
      query = if security_campaigns_draft_enabled
        autofix_enabled = CodeScanning::Autofix.any_enabled_for_org?(this_organization)
        template.build_query(autofix_enabled)
      end

      {
        id: id,
        name: template.name,
        description: template.description,
        href: security_center_alerts_code_scanning_path(this_organization, template: id),
        query:
      }
    end

    payload = {
      openCampaignsCount: visible_campaign_counts.open_campaigns_count,
      openCampaignsTotalCount: visible_campaign_counts.open_campaigns_total_count,
      openCampaignsOpenCount: visible_campaign_counts.open_campaigns_open_count,
      openCampaignsInProgressCount: visible_campaign_counts.open_campaigns_in_progress_count,
      openCampaignsFixedCount: visible_campaign_counts.open_campaigns_fixed_count,
      openCampaignsDismissedCount: visible_campaign_counts.open_campaigns_dismissed_count,

      closedCampaignsCount: visible_campaign_counts.closed_campaigns_count,
      closedCampaignsTotalCount: visible_campaign_counts.closed_campaigns_total_count,
      closedCampaignsOpenCount: visible_campaign_counts.closed_campaigns_open_count,
      closedCampaignsFixedCount: visible_campaign_counts.closed_campaigns_fixed_count,
      closedCampaignsDismissedCount: visible_campaign_counts.closed_campaigns_dismissed_count,

      draftCampaignsCount: visible_campaign_counts.draft_campaigns_count,
      autofixMetricsEnabled: current_user.feature_enabled?(:security_campaigns_autofix_metrics),
      autofixGeneratedCount: visible_campaign_counts.autofix_generated_count,
      autofixAppliedCount: visible_campaign_counts.autofix_applied_count,

      organizationLogin: this_organization.display_login,
      showFullView: can_manage_security_products,

      aboutCampaignsDocsUrl: SecurityCampaigns.about_docs_url,
      templates:,
      draftCampaignsEnabled: security_campaigns_draft_enabled,

      maxOpenCampaigns: SecurityCampaigns::MAX_OPEN_CAMPAIGNS_COUNT,
      maxDraftCampaigns: SecurityCampaigns::MAX_DRAFT_CAMPAIGNS_COUNT,
    }

    render_react_app(
      app_name: "security-campaigns",
      payload:,
      title: "Security · Campaigns",
      layout: "layouts/security_center/with_sidebar",
      page_data: { data: },
      disable_ssr: true
    )
  end

  def new
    return render_404 if !SecurityCampaigns.drafts_enabled?(current_user)

    # For regular org members with partial repo access, we need to show a warning if they've exceeded the max number of repos we show.
    _, repo_limit_exceeded = allowed_repo_ids_and_limit_exceeded

    data = log_timing(step: "build layout data") do
      {
        backfill_in_progress: this_organization.trigger_security_center_reconciliation,
        selected_tab: :campaigns,
      }
    end

    template_id = params[:template].is_a?(String) ? params[:template].to_sym : nil
    template = SecurityCampaigns::CampaignTemplates::ALL_TEMPLATES[template_id]
    if template.present?
      campaign_name = template.name
      campaign_description = template.description
    end

    source_campaign_number = params[:source_campaign_number]
    if SecurityCampaigns.campaigns_ga_enabled?(current_user) && source_campaign_number.present?
      return head :bad_request if template_id.present?

      source_campaign = SecurityCampaigns::SecurityCampaign.published.find_by(number: source_campaign_number, organization: this_organization)

      if source_campaign.present?
        campaign_name = source_campaign.name
        campaign_description = source_campaign.description
      end
    end

    payload = {
      organizationLogin: this_organization.display_login,
      currentUser: serialized_campaign_user(user: current_user),
      orgDraftCampaignsCount: SecurityCampaigns::SecurityCampaign.draft.where(organization_id: this_organization.id).count,
      maxDraftCampaigns: SecurityCampaigns::MAX_DRAFT_CAMPAIGNS_COUNT,
      orgOpenCampaignsCount: SecurityCampaigns::SecurityCampaign.open.where(organization_id: this_organization.id).count,
      maxOpenCampaigns: SecurityCampaigns::MAX_OPEN_CAMPAIGNS_COUNT,
      maxManagers: SecurityCampaigns::MAX_MANAGER_COUNT,
      customPropertyNames: custom_property_names,
      showNewAutofixFilters: current_user.feature_enabled?(:autofix_alert_filter),
      showIncompleteDataWarning: !can_view_all_alerts? && repo_limit_exceeded,
      incompleteDataWarningDocHref: ::SecurityCenter::LimitedRepoWarningComponent::PERMISSIONS_DOC_HREF,
      campaignName: campaign_name,
      campaignDescription: campaign_description,
    }

    render_react_app(
      app_name: "security-campaigns",
      payload:,
      title: "Security · Create a new campaign",
      layout: "layouts/security_center/with_sidebar",
      page_data: { data: },
      disable_ssr: true
    )
  end

  def create
    opening_details = campaign_opening_details_from_params(this_organization, current_user)
    return opening_details if opening_details.is_a?(String)

    org_campaigns_count = SecurityCampaigns::SecurityCampaign.open.where(organization_id: this_organization.id).count
    return render status: 400, json: { message: SecurityCampaigns::MAX_OPEN_CAMPAIGNS_CREATION_ERROR_MESSAGE } if org_campaigns_count >= SecurityCampaigns::MAX_OPEN_CAMPAIGNS_COUNT

    campaign = begin
      SecurityCampaigns::CreationService.call(opening_details:, actor: T.must(current_user))
    rescue ActiveRecord::RecordNotSaved => e
      return render status: 400, json: { message: e.message }
    rescue ActiveRecord::RecordInvalid => e
      if e.record.errors.any? { |r| r.type == :rate_limited }
        # unable to use 429 as that status code results in a re-direct to a 429 status page
        return render status: 403, json: { message: "Too many campaigns are being created in this organization at this moment. Please try again later." }
      else
        return render status: 422, json: { message: e.message }
      end
    rescue SecurityCampaigns::TurboscanError => e
      return render status: 500, json: { message: "An error occurred while creating the security campaign, please try again later." }
    end

    flash[:notice] = campaign_open_flash_message(opening_details, SecurityCampaigns.drafts_enabled?(this_organization) ? "published" : "created")

    render status: 200, json: {
      message: "Campaign created successfully",
      campaignNumber: campaign.number,
    }
  end

  def show
    campaign = find_security_campaign(number: params[:number].to_i, include_draft: SecurityCampaigns.drafts_enabled?(current_user))
    return render_404 if campaign.nil?
    user = current_user
    return render_404 if user.nil?

    # For regular org members with partial repo access, we need to show a warning if they've exceeded the max number of repos we show.
    _, repo_limit_exceeded = allowed_repo_ids_and_limit_exceeded

    open_org_campaigns_count = SecurityCampaigns::SecurityCampaign.open.where(organization_id: this_organization.id).count if campaign.draft?

    payload = {
      campaign: serialized_campaign(security_campaign: campaign, owner_display_login: this_organization.display_login, current_user:),
      organizationLogin: this_organization.display_login,
      currentUser: serialized_campaign_user(user: current_user),
      customPropertyNames: custom_property_names,
      maxManagers: SecurityCampaigns::MAX_MANAGER_COUNT,
      maxAlerts: SecurityCampaigns::MAX_ALERTS_COUNT,
      orgId: current_organization.id,
      showNewAutofixFilters: user.feature_enabled?(:autofix_alert_filter),
      showCampaignManagementActions: can_manage_security_products?,
      showIncompleteDataWarning: !can_view_all_alerts? && repo_limit_exceeded,
      incompleteDataWarningDocHref: ::SecurityCenter::LimitedRepoWarningComponent::PERMISSIONS_DOC_HREF,
      indexPageEnabled: SecurityCampaigns.enabled?(this_organization) && SecurityCampaigns.campaigns_ga_enabled?(current_user),
      campaignsGAEnabled: SecurityCampaigns.campaigns_ga_enabled?(current_user),
      draftCampaignsEnabled: SecurityCampaigns.drafts_enabled?(current_user),
      openOrgCampaignsCount: open_org_campaigns_count,
      maxCampaigns: SecurityCampaigns::MAX_OPEN_CAMPAIGNS_COUNT,
    }

    selected_tab = if SecurityCampaigns.campaigns_ga_enabled?(current_user)
      :campaigns
    elsif campaign.closed?
      :security_campaign_closed_campaigns
    else
      "security_campaign_#{campaign.number}".to_sym
    end

    data = log_timing(step: "build layout data") do
      {
        backfill_in_progress: this_organization.trigger_security_center_reconciliation,
        selected_tab:,
      }
    end

    render_react_app(
      app_name: "security-campaigns",
      payload:,
      title: "Security · #{campaign.name}",
      layout: "layouts/security_center/with_sidebar",
      page_data: { data: },
      disable_ssr: true
    )
  end

  def update
    campaign = SecurityCampaigns::SecurityCampaign.find_by(number: params[:number], organization: this_organization.id)
    return render_404 if campaign.nil?

    return render status: 422, json: { message: "Draft campaigns cannot be edited from this endpoint" } if campaign.draft?
    return render status: 422, json: { message: "Closed campaigns cannot be updated" } if campaign.closed?
    return render status: 422, json: { message: "Campaign name required" } if params[:campaign_name].blank?
    return render status: 422, json: { message: "Campaign description required" } if params[:campaign_description].blank?
    return render status: 422, json: { message: "Campaign due date required" } if params[:campaign_due_date].blank?

    managers = prepare_managers(this_organization)
    return managers unless managers.is_a?(Array)

    team_managers = prepare_team_managers(this_organization)
    return team_managers unless team_managers.is_a?(Array)

    managers_validation = validate_number_campaign_managers(user_manager_ids: managers.map(&:id), team_manager_ids: team_managers.map(&:id))
    return managers_validation if managers_validation.is_a?(String)

    contact_link = params[:campaign_contact_link]

    ends_at = Time.zone.parse(params[:campaign_due_date])
    return render status: 400, json: { message: "Invalid due date" } if ends_at.blank?

    begin
      campaign.update!(
        name: params[:campaign_name],
        description: params[:campaign_description],
        ends_at: ends_at,
        contact_link: contact_link,
        user_manager_users: managers,
        team_manager_teams: team_managers,
      )
    rescue ActiveRecord::RecordInvalid => e
      return render status: 422, json: { message: e.message }
    end

    flash_message = if SecurityCampaigns.issue_creation_enabled?(this_organization) && campaign.issues.exists?
      SecurityCampaigns::UpdateIssuesJob.perform_later(campaign_id: campaign.id)
      "Campaign details successfully updated. Updating campaign issues now."
    end

    flash[:notice] = flash_message

    render status: 200, json: { message: "Campaign updated successfully" }
  end

  def destroy
    campaign = SecurityCampaigns::SecurityCampaign.find_by(number: params[:number], organization: this_organization.id)
    return render_404 if campaign.nil?

    return render status: 422, json: { message: "Draft campaigns cannot be deleted from this endpoint" } if campaign.draft?

    SecurityCampaigns::DeletionService.call(campaign: campaign, actor: T.must(current_user))

    flash[:notice] = "The campaign \"#{campaign.name}\" was successfully deleted."

    render status: 200, json: { message: "Campaign deleted successfully" }
  end

  private

  sig { returns(T::Array[String]) }
  def custom_property_names
    ::SecurityCenter::Helpers::CustomProperties.new(org: this_organization, user: current_user).definitions_for_frontend.map do |item|
      item.fetch(:name)
    end
  end
end
