# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::SecurityCampaignAlertsGroupsController < Orgs::SecurityCenter::AbstractSecurityCampaignsController
  extend T::Sig
  include Orgs::SecurityCenter::CodeScanningOrgQueriesHelper

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

  def index
    campaign = SecurityCampaigns::SecurityCampaign.find_by(number: params[:number], organization: this_organization.id)
    return render_404 if campaign.nil?

    query_string = params[:query].try(:to_str)

    after_cursor = params[:after].try(:to_str)
    before_cursor = params[:before].try(:to_str)

    group_string = params[:group].try(:to_str)

    allowed_repo_ids, _repo_limit_exceeded = allowed_repo_ids_and_limit_exceeded

    query_service = CodeScanning::AlertQueryService.for_organization(
      user: current_user,
      user_session: user_session,
      organization: this_organization,
      allowed_repository_ids: allowed_repo_ids,
      query: query_string,
      visibility: SecurityCampaigns::REPOSITORY_VISIBILITIES,
    )

    campaign_with_counts = SecurityCampaigns::CampaignWithGroupedCounts.load(campaign, query_string:, after_cursor:, before_cursor:, query_service:)

    payload = {
      openCount: campaign_with_counts.open_count,
      closedCount: campaign_with_counts.closed_count,
      nextCursor: campaign_with_counts.next_cursor,
      prevCursor: campaign_with_counts.prev_cursor,
      groups: campaign_with_counts.groups.map do |group|
        {
          title: group.title,
          repositories: group.repositories.map(&:name),
          openCount: group.open_count,
          closedCount: group.closed_count,
        }
      end,
    }

    render json: payload
  end
end
