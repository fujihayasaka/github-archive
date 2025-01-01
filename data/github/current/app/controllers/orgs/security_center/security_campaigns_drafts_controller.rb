# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::SecurityCampaignsDraftsController < Orgs::SecurityCenter::AbstractSecurityCampaignsController
  include Orgs::SecurityCenter::CodeScanningOrgQueriesHelper
  include SecurityCampaigns::ManagersDependency
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include SecurityCampaigns::CampaignsSerializer

  before_action :manage_security_products_permission_required

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "Orgs::SecurityCenter::SecurityCampaignsDraftsController#create",
    "Orgs::SecurityCenter::SecurityCampaignsDraftsController#update",
    "Orgs::SecurityCenter::SecurityCampaignsDraftsController#destroy"
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
    only: [:index, :create, :update, :destroy]

  depends_on_clusters \
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::SecurityOverviewAnalytics,
    only: [:index, :create, :update, :destroy],
    optional: true

  allow_verified_fetch only: [:index, :create, :update, :destroy]
  before_action :try_parse_json_params, only: [:create, :update]

  def index
    alert_type = if SecurityCampaigns::SecurityCampaign::KNOWN_ALERT_TYPES.include?(params[:alert_type])
      params[:alert_type]
    else
      "code_scanning"
    end

    draft_campaigns = SecurityCampaigns::SecurityCampaign.draft.where(organization: this_organization)
    if FeatureFlag.vexi.enabled?(:secret_scanning_campaigns, current_user, this_organization, this_organization.business, default: false)
      draft_campaigns = draft_campaigns.for_alert_type(alert_type)
    end
    draft_campaigns = draft_campaigns.filter_spam_for(current_user)
    draft_campaigns = draft_campaigns.order(created_at: :desc).to_a

    visible_teams = this_organization.visible_teams_for(current_user).to_a

    owner_display_login = this_organization.display_login
    payload = {
      campaigns: draft_campaigns.map do |security_campaign|
        serialized_campaign(security_campaign:, owner_display_login:, current_user:, visible_teams:)
      end
    }

    render json: payload
  end

  def create
    upsert_params = get_and_validate_upsert_params
    return upsert_params if upsert_params.is_a?(String)

    org_draft_campaigns_count = SecurityCampaigns::SecurityCampaign.draft.where(organization_id: this_organization.id).count
    return render status: 400, json: { message: SecurityCampaigns::MAX_DRAFT_CAMPAIGNS_CREATION_ERROR_MESSAGE } if org_draft_campaigns_count >= SecurityCampaigns::MAX_DRAFT_CAMPAIGNS_COUNT

    draft_campaign = begin
      new_campaign = SecurityCampaigns::SecurityCampaign.new(
        organization: this_organization,
        name: upsert_params.name,
        contact_link: upsert_params.contact_link,
        user_manager_users: upsert_params.managers,
        team_manager_teams: upsert_params.team_managers,
        description: upsert_params.description,
        creation_query: upsert_params.query_string,
        alert_type: upsert_params.alert_type,
        published_at: nil,
        created_by: current_user,
      )
      SecurityCampaigns::DraftCreationService.call(campaign: new_campaign, actor: current_user)
    rescue ActiveRecord::RecordNotSaved => e
      return render status: 400, json: { message: e.message }
    rescue ActiveRecord::RecordInvalid => e
      if e.record.errors.any? { |r| r.type == :rate_limited }
        # unable to use 429 as that status code results in a re-direct to a 429 status page
        return render status: 403, json: { message: "Too many draft campaigns are being created in this organization at this moment. Please try again later." }
      else
        return render status: 422, json: { message: e.message }
      end
    end

    render status: 200, json: {
      message: "Draft campaign created successfully",
      campaignNumber: draft_campaign.number,
    }
  end

  def update
    campaign_number = params[:number].to_i

    draft_campaigns = SecurityCampaigns::SecurityCampaign.draft
    draft_campaigns = draft_campaigns.filter_spam_for(current_user)
    campaign = draft_campaigns.includes(:user_manager_users, team_manager_teams: :organization).find_by(number: campaign_number, organization: this_organization.id)
    return render_404 if campaign.nil?

    upsert_params = get_and_validate_upsert_params
    return upsert_params if upsert_params.is_a?(String)

    query_changed = upsert_params.query_string != campaign.creation_query

    begin
      campaign.update!(
        name: upsert_params.name,
        description: upsert_params.description,
        user_manager_users: upsert_params.managers,
        team_manager_teams: upsert_params.team_managers,
        contact_link: upsert_params.contact_link,
        creation_query: upsert_params.query_string,
      )
    rescue ActiveRecord::RecordInvalid => e
      return render status: 422, json: { message: e.message }
    end

    GlobalInstrumenter.instrument("security_campaigns.security_campaign_update", {
      actor: current_user,
      security_campaign: campaign,
      query_changed:,
    })

    render status: 200, json: {
      campaign: serialized_campaign(security_campaign: campaign, owner_display_login: this_organization.display_login, current_user:),
    }
  end

  def destroy
    draft_campaigns = SecurityCampaigns::SecurityCampaign.draft
    draft_campaigns = draft_campaigns.filter_spam_for(current_user)
    campaign = draft_campaigns.find_by(number: params[:number], organization: this_organization.id)
    return render_404 if campaign.nil?

    campaign.destroy!

    GlobalInstrumenter.instrument("security_campaigns.security_campaign_delete", {
      actor: current_user,
      security_campaign: campaign,
    })

    render json: {
      showFlashMessage: true,
    }
  end

  private

  sig { returns(T.any(UpsertParams, String)) }
  def get_and_validate_upsert_params
    name = params[:campaign_name]
    return render status: 422, json: { message: "Campaign name required" } if name.blank?

    description = params[:campaign_description]

    managers = prepare_managers(this_organization)

    return managers unless managers.is_a?(Array)

    team_managers = prepare_team_managers(this_organization)
    return team_managers unless team_managers.is_a?(Array)

    managers_validation = validate_number_campaign_managers(user_manager_ids: managers.map(&:id), team_manager_ids: team_managers.map(&:id))
    return managers_validation if managers_validation.is_a?(String)

    contact_link = params[:campaign_contact_link]

    alert_type = params[:alert_type] || "code_scanning"
    return render status: 422, json: { message: "Unknown alert_type" } unless SecurityCampaigns::SecurityCampaign::KNOWN_ALERT_TYPES.include?(alert_type)

    return render status: 422, json: { message: "Invalid query" } if !query.is_valid?

    UpsertParams.new(
      name:,
      description:,
      query_string:,
      managers:,
      team_managers:,
      contact_link:,
      alert_type:,
    )
  end

  class UpsertParams < T::Struct
    const :name, String
    const :description, T.nilable(String)
    const :query_string, String
    const :managers, T::Array[User]
    const :team_managers, T::Array[Team]
    const :contact_link, T.nilable(String)
    const :alert_type, String
  end

end
