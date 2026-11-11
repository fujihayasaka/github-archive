# typed: true
# frozen_string_literal: true

class Repos::SecurityCampaigns::RepositoriesController < Repos::SecurityCampaigns::BaseRepositoryController
  include SecurityCampaigns::CampaignsSerializer
  include CodeScanning::AlertsSerializer

  before_action :check_user_has_view_permission

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
    ApplicationRecord::RepositoriesPushes,
    only: [:show],
    optional: true

  def show
    scope = SecurityCampaigns::SecurityCampaign.open
    scope = scope.filter_spam_for(current_user)
    campaign = scope.includes(:user_manager_users, team_manager_teams: :organization).
      find_by(number: params[:number], organization: current_repository.owner_id)

    return render_404 if campaign.nil?
    if T.must(campaign).alert_type == "secret_scanning"
      return render_404 unless FeatureFlag.vexi.enabled?(:secret_scanning_campaigns, current_user, current_repository, current_repository.owner, current_repository.owner&.business, default: false)
      token_scanning = SecretScanning::Features::Repo::TokenScanning.new(current_repository)
      return render_404 unless token_scanning.view_alerts_allowed?(current_user)
    else
      return render_404 if campaign.alert_type == "code_scanning" && !current_repository.code_scanning_readable_by?(current_user)
    end

    if T.must(campaign).alert_type == "secret_scanning"
      query_service = SecretScanning::AlertQueryService.for_organization(
        organization: current_repository.owner,
        security_campaign_ids: [campaign.id],
        current_user:,
        user_session:,
        allowed_repository_ids: [current_repository.id],
      )
    else
      query_service = CodeScanning::AlertQueryService.for_organization(
        user: current_user,
        user_session: user_session,
        organization: current_repository.owner,
        security_campaign_ids: [campaign.id],
        allowed_repository_ids: [current_repository.id],
      )
    end
    campaign_with_count = SecurityCampaigns::CampaignWithCounts.for_repo_with_alerts(
      security_campaigns: [campaign],
      query_service:,
    ).first
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
      branchListCacheKey: helpers.ref_list_cache_key(repository: current_repository),
      showOrgCampaignLink: current_repository.owner.organization? && current_repository.owner.direct_or_team_member?(current_user),
      showHubberWarning: current_repository.code_scanning_readable_because_hubber?(current_user),
      canCreateBranch: current_user_can_push?,
      canCloseAlerts: current_repository.code_scanning_writable_by?(current_user),
      issue: issue_payload,
      delegatedAlertDismissalEnabled: CodeScanning::AlertDismissalService.new(current_repository).delegated_dismissal_enabled?,
      showAssignToCopilotButton: autofix_assign_to_copilot_button_enabled?,
      canAssignAlertsToCopilot: autofix_assign_to_copilot_button_enabled? && current_repository.copilot_swe_agent_enabled?(current_user),
      canRegenerateFixes: campaign.alert_type == "secret_scanning" ? false : show_autofix_regenerate_button?,
      copilotCodingAgentDocsUrl: copilot_coding_agent_docs_url,
      canSelectSecretScanningAlerts: SecretScanning::Features::FeatureFlagHelper.feature_flag_enabled_in_hierarchy?(current_repository, SecretScanning::Features::FeatureFlagHelper::FeatureFlags::CAMPAIGNS_SELECT_ALERTS),
    }

    render_react_app(
      payload: payload,
      title: campaign.name + " · Security Campaign",
      layout: "layouts/security_campaigns/repositories_sidebar_container",
      layout_locals_generator: -> { { security_campaign_number: campaign.number } },
      disable_ssr: true
    )
  end

  private

  def copilot_coding_agent_docs_url
    "#{GitHub.help_url}/copilot/how-tos/agents/copilot-coding-agent/enabling-copilot-coding-agent"
  end

  def autofix_assign_to_copilot_button_enabled?
    current_repository.writable_by?(current_user) && current_repository.code_scanning_writable_by?(current_user) &&
      current_repository.owner.feature_flag_enabled?(:copilot_security_alert_assignee_options, default: false)
  end

  def show_autofix_regenerate_button?
    current_repository.code_scanning_writable_by?(current_user) &&
      CodeScanning::Autofix.any_enabled_for_repo?(current_repository) &&
      CodeScanning::AutofixService.agentic_autofix_validation_checks_enabled?(current_repository) &&
      CodeScanning::AutofixService.iterative_autofix_regenerate_button_enabled?(current_repository)
  end

  sig { void }
  def check_user_has_view_permission
    return if SecretScanning::Features::Repo::TokenScanning.new(current_repository).view_alerts_allowed?(current_user) || current_repository.code_scanning_readable_by?(current_user)
    render_404
  end
end
