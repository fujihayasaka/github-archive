# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::ClosedSecurityCampaignsListController < Orgs::SecurityCenter::AbstractSecurityCampaignsController
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

    campaigns_relation = Platform::ConnectionWrappers::Relation.new(
      SecurityCampaigns::SecurityCampaign.closed.where(organization: this_organization).order(closed_at: :desc, number: :desc),
      max_page_size: CLOSED_CAMPAIGNS_PER_PAGE,
      after: after_cursor,
      before: before_cursor,
      first:,
      last:
    )

    campaigns_with_counts = SecurityCampaigns::CampaignWithCounts.load(security_campaigns: campaigns_relation.edge_nodes.sync, user: current_user)

    owner_display_login = this_organization.display_login
    payload = {
      campaigns: campaigns_with_counts.map { |campaign_with_counts| serialized_campaign_with_counts(campaign_with_counts:, owner_display_login:) },
      nextCursor: campaigns_relation.page_info.has_next_page ? campaigns_relation.page_info.end_cursor : nil,
      prevCursor: campaigns_relation.page_info.has_previous_page ? campaigns_relation.page_info.start_cursor : nil,
    }

    render status: 200, json: payload
  end
end
