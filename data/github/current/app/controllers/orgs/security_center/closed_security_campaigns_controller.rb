# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::ClosedSecurityCampaignsController < Orgs::SecurityCenter::AbstractSecurityCampaignsController
  include SecurityCampaigns::CampaignsSerializer
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :manage_security_products_permission_required

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
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    ApplicationRecord::SecurityOverviewAnalytics,
    only: [:index],
    optional: true

  allow_verified_fetch only: [:index]
  before_action :try_parse_json_params, only: [:index]

  CLOSED_CAMPAIGNS_PER_PAGE = 10

  def index
    after_cursor = params[:after]
    before_cursor = params[:before]

    first, last = before_cursor.presence ? [nil, CLOSED_CAMPAIGNS_PER_PAGE] : [CLOSED_CAMPAIGNS_PER_PAGE, nil]

    alert_type = if SecurityCampaigns::SecurityCampaign::KNOWN_ALERT_TYPES.include?(params[:alert_type])
      params[:alert_type]
    else
      "code_scanning"
    end

    closed_campaigns = SecurityCampaigns::SecurityCampaign.closed.where(organization: this_organization)
    if FeatureFlag.vexi.enabled?(:secret_scanning_campaigns, current_user, this_organization, this_organization.business, default: false)
      closed_campaigns = closed_campaigns.for_alert_type(alert_type)
    end
    closed_campaigns = closed_campaigns.filter_spam_for(current_user)
    campaigns_relation = Platform::ConnectionWrappers::Relation.new(
      closed_campaigns.order(closed_at: :desc, number: :desc),
      max_page_size: CLOSED_CAMPAIGNS_PER_PAGE,
      after: after_cursor,
      before: before_cursor,
      first:,
      last:
    )
    campaigns = campaigns_relation.edge_nodes.sync
    GitHub::PrefillAssociations.prefill_associations(campaigns, { organization: [], user_manager_users: [], team_manager_teams: :organization }, available_records: [this_organization])

    query_service = CodeScanning::AlertQueryService.for_organization(
      user: current_user,
      user_session:,
      organization: this_organization,
      security_campaign_ids: campaigns.map(&:id),
    )
    campaigns_with_counts = SecurityCampaigns::CampaignWithCounts.load(security_campaigns: campaigns, query_service:)

    visible_teams = this_organization.visible_teams_for(current_user).to_a
    owner_display_login = this_organization.display_login
    payload = {
      campaigns: campaigns_with_counts.map { |campaign_with_counts| serialized_campaign_with_counts(campaign_with_counts:, owner_display_login:, current_user:, visible_teams:) },
      nextCursor: campaigns_relation.page_info.has_next_page ? campaigns_relation.page_info.end_cursor : nil,
      prevCursor: campaigns_relation.page_info.has_previous_page ? campaigns_relation.page_info.start_cursor : nil,
    }

    render status: 200, json: payload
  end
end
