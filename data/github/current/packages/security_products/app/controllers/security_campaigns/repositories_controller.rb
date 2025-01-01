# typed: true
# frozen_string_literal: true

class SecurityCampaigns::RepositoriesController < SecurityCampaigns::BaseRepositoryController
  include CodeScanningHelper
  include ReactHelper
  include ScanningHelper
  include SecurityCampaigns::CampaignsSerializer
  include SecurityCampaigns::RepositoriesSerializer

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
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    only: [:show],
    optional: true

  def show
    campaign =
      SecurityCampaigns::SecurityCampaign.open.
      for_repo_with_alerts(current_repository).
      find_by(number: params[:number], organization: current_repository.owner_id)

    return render_404 if campaign.nil?

    payload = {
      campaign: serialized_campaign(security_campaign: campaign, owner_display_login: current_repository.owner_display_login),
      repository: serialized_repository(repository: current_repository),
      alertsPath: repository_security_campaign_alerts_path,
      createBranchPath: current_user_can_push? ? create_security_campaign_alert_branch_path : nil,
      closeAlertsPath: close_security_campaign_alerts_path
    }

    render_react_app(
      payload: payload,
      title: campaign.name + " · Security Campaign",
      layout: "layouts/security_campaigns/repositories_sidebar_container",
      layout_locals_generator: -> { { security_campaign_number: campaign.number } },
      ssr: false
    )
  end
end
