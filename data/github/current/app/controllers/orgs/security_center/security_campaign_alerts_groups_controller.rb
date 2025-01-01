# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::SecurityCampaignAlertsGroupsController < Orgs::SecurityCenter::AbstractSecurityCampaignsController
  include Orgs::SecurityCenter::CodeScanningOrgQueriesHelper
  include CodeScanning::AlertsSerializer

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
    ApplicationRecord::IssuesPullRequests,
    only: [:index]

  def index
    campaign = find_security_campaign(number: params[:number].to_i)
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
      security_campaign_ids: [T.must(campaign.id)],
    )

    campaign_with_counts = SecurityCampaigns::CampaignWithGroupedCounts.load(
      security_campaign: campaign,
      user: current_user,
      query_string:,
      after_cursor:,
      before_cursor:,
      query_service:
    )

    campaign_issues = if SecurityCampaigns.issue_creation_enabled?(T.must(campaign.organization))
      repos = campaign_with_counts.groups.flat_map(&:repositories)
      campaign.security_campaign_issues.includes(issue: :repository).where(repository: repos)
    end

    payload = {
      openCount: campaign_with_counts.open_count,
      closedCount: campaign_with_counts.closed_count,
      nextCursor: campaign_with_counts.next_cursor,
      prevCursor: campaign_with_counts.prev_cursor,
      groups: campaign_with_counts.groups.map do |group|
        issue_payload = issue(campaign_issues, group.repositories)

        group_payload = {
          kind: "repository",
          repository: serialized_repository(repository: T.must(group.repositories.first)),
        } if group.repositories.first

        groups_payload = {
          title: group.title,
          repositories: group.repositories.map(&:name),
          group: group_payload,
          openCount: group.open_count,
          closedCount: group.closed_count,
          openWithLinksCount: group.open_with_links_count,
        }

        groups_payload[:issue] = issue_payload if issue_payload

        groups_payload
      end,
    }

    render json: payload
  end

  private

  def issue(campaign_issues, repositories)
    # Get the first repository in the group since we only support grouping by repository for now
    repository = repositories.first
    issue_payload = nil

    return issue_payload unless repository && campaign_issues

    campaign_issue = campaign_issues.find { |campaign_issue| campaign_issue.repository_id == repository.id } # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    if campaign_issue
      issue = campaign_issue.issue_following_transfers
      return issue_payload unless issue

      issue_payload = {
        number: issue.number,
        repo: issue.repository.name,
        owner: issue.repository.owner_display_login,
        state: issue.state,
        stateReason: issue.state_reason,
      }
    end

    issue_payload
  end
end
