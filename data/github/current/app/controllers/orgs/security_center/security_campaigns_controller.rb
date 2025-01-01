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
    return render_404 if !SecurityCampaigns.enabled?(this_organization)

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
    templates = SecurityCampaigns::CampaignTemplates::ALL_TEMPLATES.map do |id, template|
      autofix_enabled = CodeScanning::Autofix.any_enabled_for_org?(this_organization)
      query = template.build_query(autofix_enabled)

      {
        id: id,
        name: template.name,
        description: template.description,
        href: security_center_alerts_code_scanning_path(this_organization, template: id),
        query:
      }
    end

    payload = {
      campaignCounts: visible_campaign_counts.to_react_payload,

      autofixMetricsEnabled: current_user.feature_enabled?(:security_campaigns_autofix_metrics),

      organizationLogin: this_organization.display_login,
      showFullView: can_manage_security_products,

      aboutCampaignsDocsUrl: SecurityCampaigns.about_docs_url,
      templates:,

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
    if source_campaign_number.present?
      return head :bad_request if template_id.present?

      published_campaigns = SecurityCampaigns::SecurityCampaign.published
      published_campaigns = published_campaigns.filter_spam_for(current_user)
      source_campaign = published_campaigns.find_by(number: source_campaign_number, organization: this_organization)

      if source_campaign.present?
        campaign_name = source_campaign.name
        campaign_description = source_campaign.description
      end
    end

    draft_campaigns = SecurityCampaigns::SecurityCampaign.draft.where(organization_id: this_organization.id).to_a
    open_campaigns = SecurityCampaigns::SecurityCampaign.open.where(organization_id: this_organization.id).to_a
    payload = {
      organizationLogin: this_organization.display_login,
      currentUser: serialized_campaign_user(user: current_user),
      orgDraftCampaignsCount: draft_campaigns.count,
      maxDraftCampaigns: SecurityCampaigns::MAX_DRAFT_CAMPAIGNS_COUNT,
      orgOpenCampaignsCount: open_campaigns.count,
      maxOpenCampaigns: SecurityCampaigns::MAX_OPEN_CAMPAIGNS_COUNT,
      maxManagers: SecurityCampaigns::MAX_MANAGER_COUNT,
      customPropertyNames: custom_property_names,
      showNewAutofixFilters: current_user.feature_enabled?(:autofix_alert_filter),
      showIncompleteDataWarning: !can_view_all_alerts? && repo_limit_exceeded,
      incompleteDataWarningDocHref: ::SecurityCenter::LimitedRepoWarningComponent::PERMISSIONS_DOC_HREF,
      showLimitedAlertsWarning: !can_view_all_alerts?,
      campaignName: campaign_name,
      campaignDescription: campaign_description,
      maxAlerts: SecurityCampaigns::MAX_ALERTS_COUNT,
      bestPracticeCampaignsDocsUrl: SecurityCampaigns.best_practice_docs_url,
      hasOpenSpam: open_campaigns.any? { |campaign| campaign.hide_from_user?(current_user) },
      hasDraftSpam: draft_campaigns.any? { |campaign| campaign.hide_from_user?(current_user) }
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

    message = campaign_open_flash_message(opening_details, "published")
    render status: 200, json: {
      message:,
      showFlashMessage: true,
      campaignNumber: campaign.number,
    }
  end

  def show
    campaign = find_security_campaign(number: params[:number].to_i, include_draft: true)
    return render_404 if campaign.nil?
    user = current_user
    return render_404 if user.nil?

    # For regular org members with partial repo access, we need to show a warning if they've exceeded the max number of repos we show.
    _, repo_limit_exceeded = allowed_repo_ids_and_limit_exceeded

    open_org_campaigns = SecurityCampaigns::SecurityCampaign.open.where(organization_id: this_organization.id).to_a if campaign.draft?

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
      showLimitedAlertsWarning: !can_view_all_alerts?,
      indexPageEnabled: SecurityCampaigns.enabled?(this_organization),
      openOrgCampaignsCount: open_org_campaigns&.count,
      maxCampaigns: SecurityCampaigns::MAX_OPEN_CAMPAIGNS_COUNT,
      bestPracticeCampaignsDocsUrl: SecurityCampaigns.best_practice_docs_url,
      hasOpenSpam: campaign.draft? && (open_org_campaigns || []).any? { |campaign| campaign.hide_from_user?(current_user) }
    }

    selected_tab = :campaigns

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
    return render_404 if campaign.nil? || campaign.hide_from_user?(current_user)

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

    GlobalInstrumenter.instrument("security_campaigns.security_campaign_update", {
      actor: current_user,
      security_campaign: campaign,
    })

    flash_message = if SecurityCampaigns.issue_creation_enabled?(this_organization) && campaign.issues.exists? # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      SecurityCampaigns::UpdateIssuesJob.perform_later(campaign_id: campaign.id)
      "Campaign details successfully updated. Updating campaign issues now."
    end

    render status: 200, json: {
      campaign: serialized_campaign(security_campaign: campaign, owner_display_login: this_organization.display_login, current_user:),
      message: flash_message,
      showFlashMessage: true,
    }
  end

  def destroy
    campaign = SecurityCampaigns::SecurityCampaign.find_by(number: params[:number], organization: this_organization.id)
    return render_404 if campaign.nil? || campaign.hide_from_user?(current_user)

    return render status: 422, json: { message: "Draft campaigns cannot be deleted from this endpoint" } if campaign.draft?

    SecurityCampaigns::DeletionService.call(campaign: campaign, actor: T.must(current_user))

    render status: 200, json: {
      showFlashMessage: true,
    }
  end

  private

  sig { returns(T::Array[String]) }
  def custom_property_names
    ::SecurityCenter::Helpers::CustomProperties.new(org: this_organization, user: current_user).definitions_for_frontend.map do |item|
      item.fetch(:name)
    end
  end
end
