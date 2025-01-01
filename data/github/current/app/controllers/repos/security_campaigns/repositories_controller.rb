# typed: true
# frozen_string_literal: true

class Repos::SecurityCampaigns::RepositoriesController < Repos::SecurityCampaigns::BaseRepositoryController
  include SecurityCampaigns::CampaignsSerializer
  include CodeScanning::AlertsSerializer

  before_action :check_code_scanning_read

  def self.react_bundle_name
    "security-campaigns"
  end

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
    ApplicationRecord::Ballast,
    ApplicationRecord::Iam,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    only: [:show],
    optional: true

  def show
    campaign = SecurityCampaigns::SecurityCampaign.includes(:user_manager_users, team_manager_teams: :organization).open.
      find_by(number: params[:number], organization: current_repository.owner_id)

    campaign_with_count = SecurityCampaigns::CampaignWithCounts.for_repo_with_alerts(
      security_campaigns: [campaign], repo: current_repository, user: T.must(current_user)
    ).first unless campaign.nil?
    campaign = campaign_with_count&.security_campaign

    return render_404 if campaign.nil?

    issue_payload = nil
    if SecurityCampaigns.issue_creation_enabled?(T.must(campaign.organization))
      issue = SecurityCampaigns::SecurityCampaignIssue.find_by(security_campaign: campaign, repository: current_repository)&.issue_following_transfers

      if issue
        issue_payload = {
          number: issue.number,
          repo: issue.repository&.name,
          owner: issue.repository&.owner_display_login,
          state: issue.state,
          stateReason: issue.state_reason,
        }
      end
    end

    payload = {
      campaign: serialized_campaign(security_campaign: campaign, owner_display_login: current_repository.owner_display_login, current_user:),
      repository: serialized_repository(repository: current_repository),
      showOrgCampaignLink: current_repository.owner.organization? && current_repository.owner.direct_or_team_member?(current_user),
      showHubberWarning: current_repository.code_scanning_readable_because_hubber?(current_user),
      canCreateBranch: current_user_can_push?,
      canCloseAlerts: current_repository.code_scanning_writable_by?(current_user),
      issue: issue_payload,
      delegatedAlertDismissalEnabled: CodeScanning::AlertDismissalService.new(current_repository).enabled?,
      campaignsGAEnabled: SecurityCampaigns.campaigns_ga_enabled?(current_user),
    }

    render_react_app(
      payload: payload,
      title: campaign.name + " · Security Campaign",
      layout: "layouts/security_campaigns/repositories_sidebar_container",
      layout_locals_generator: -> { { security_campaign_number: campaign.number } },
      disable_ssr: true
    )
  end
end
