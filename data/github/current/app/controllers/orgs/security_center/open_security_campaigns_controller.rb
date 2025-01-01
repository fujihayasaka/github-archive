# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::OpenSecurityCampaignsController < Orgs::SecurityCenter::AbstractSecurityCampaignsController
  include SecurityCampaigns::CampaignsSerializer
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :organization_read_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Notify,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    ApplicationRecord::SecurityOverviewAnalytics,
    only: [:index],
    optional: true

  allow_verified_fetch only: [:index]

  def index
    return render_404 if !SecurityCampaigns.enabled?(this_organization)

    open_campaigns = SecurityCampaigns::SecurityCampaign.open.where(organization: this_organization)
    open_campaigns = open_campaigns.filter_spam_for(current_user)
    alert_type = if SecurityCampaigns::SecurityCampaign::KNOWN_ALERT_TYPES.include?(params[:alert_type])
      params[:alert_type]
    else
      "code_scanning"
    end
    if FeatureFlag.vexi.enabled?(:secret_scanning_campaigns, current_user, this_organization, this_organization.business, default: false)
      open_campaigns = open_campaigns.for_alert_type(alert_type)
    end
    all_open_campaigns = open_campaigns.order(created_at: :asc).to_a
    allowed_repository_ids = allowed_repo_ids_and_limit_exceeded&.first

    query_service = CodeScanning::AlertQueryService.for_organization(
      user: current_user,
      user_session: nil,
      organization: T.must(this_organization),
      security_campaign_ids: all_open_campaigns.map(&:id),
      allowed_repository_ids:
    )
    visible_open_campaigns = SecurityCampaigns::CampaignWithCounts.load(
      security_campaigns: all_open_campaigns, query_service:
    )
    unless can_manage_security_products?
      visible_open_campaigns.filter! do |campaign_with_counts|
        # filter out campaign with 0 counts
        campaign_with_counts.total_count.positive?
      end
    end

    visible_teams = this_organization.visible_teams_for(current_user).to_a

    owner_display_login = this_organization.display_login
    payload = {
      campaigns: visible_open_campaigns.map { |campaign_with_counts| serialized_campaign_with_counts(campaign_with_counts:, owner_display_login:, current_user:, visible_teams:) },
    }

    render status: 200, json: payload
  end
end
