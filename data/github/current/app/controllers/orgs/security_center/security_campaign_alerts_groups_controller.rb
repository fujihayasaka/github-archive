# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::SecurityCampaignAlertsGroupsController < Orgs::SecurityCenter::AbstractSecurityCampaignsController
  include Orgs::SecurityCenter::CodeScanningOrgQueriesHelper

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

  def index
    campaign = find_security_campaign(number: params[:number])
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
      security_campaign_ids: current_user.feature_enabled?(:security_campaigns_read_without_alerts_limit) ? [T.must(campaign.id)] : nil,
    )

    campaign_with_counts = SecurityCampaigns::CampaignWithGroupedCounts.load(
      security_campaign: campaign,
      user: current_user,
      query_string:,
      after_cursor:,
      before_cursor:,
      query_service:
    )

    payload = {
      openCount: campaign_with_counts.open_count,
      closedCount: campaign_with_counts.closed_count,
      nextCursor: campaign_with_counts.next_cursor,
      prevCursor: campaign_with_counts.prev_cursor,
      groups: campaign_with_counts.groups.map do |group|
        {
          title: group.title,
          titleHref: title_href(campaign, group.repositories),
          repositories: group.repositories.map(&:name),
          openCount: group.open_count,
          closedCount: group.closed_count,
          openWithLinksCount: group.open_with_links_count,
        }
      end,
    }

    render json: payload
  end

  private

  def title_href(campaign, repositories)
    # Get the first repository in the group since we only support grouping by repository for now
    repository = repositories.first

    if campaign.open?
      UrlHelpers.repository_security_campaign_path(repository:, user_id: repository.owner_display_login, number: campaign.number)
    else
      UrlHelpers.repository_path(repository.owner_display_login, repository)
    end
  end
end
