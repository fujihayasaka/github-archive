# typed: true
# frozen_string_literal: true

class Repos::SecurityCampaigns::RepositoriesController < Repos::SecurityCampaigns::BaseRepositoryController
  include ReactHelper
  include SecurityCampaigns::CampaignsSerializer
  include SecurityCampaigns::RepositoriesSerializer

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
    campaign = if T.must(current_user).feature_enabled?(:security_campaigns_read_without_alerts_limit)
      campaign = SecurityCampaigns::SecurityCampaign.open.
        find_by(number: params[:number], organization: current_repository.owner_id)

      campaign_with_count = SecurityCampaigns::CampaignWithCounts.for_repo_with_alerts(
        security_campaigns: [campaign], repo: current_repository
      ).first unless campaign.nil?
      campaign_with_count.security_campaign if campaign_with_count
    else
      SecurityCampaigns::SecurityCampaign.open.
        for_repo_with_alerts(current_repository).
        find_by(number: params[:number], organization: current_repository.owner_id)
    end
    return render_404 if campaign.nil?

    payload = {
      campaign: serialized_campaign(security_campaign: campaign, owner_display_login: current_repository.owner_display_login),
      repository: serialized_repository(repository: current_repository),
      orgCampaignPath: org_campaign_path,
      showHubberWarning: current_repository.code_scanning_readable_because_hubber?(current_user),
      alertsPath: repository_security_campaign_alerts_path,
      createBranchPath: current_user_can_push? ? create_security_campaign_alert_branch_path : nil,
      closeAlertsPath: current_repository.code_scanning_writable_by?(current_user) ? close_security_campaign_alerts_path : nil,
    }

    render_react_app(
      payload: payload,
      title: campaign.name + " · Security Campaign",
      layout: "layouts/security_campaigns/repositories_sidebar_container",
      layout_locals_generator: -> { { security_campaign_number: campaign.number } },
      ssr: false
    )
  end

  private

  def org_campaign_path
    return nil unless current_repository.owner.organization?
    return nil unless current_repository.owner.direct_or_team_member?(current_user)

    security_center_security_campaign_path(org: current_repository.owner)
  end
end
