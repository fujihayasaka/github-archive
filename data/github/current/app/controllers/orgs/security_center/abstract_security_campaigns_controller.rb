# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::AbstractSecurityCampaignsController < Orgs::SecurityCenter::AbstractSecurityCenterController
  include Orgs::SecurityCenter::CodeScanningOrgQueriesHelper
  include Orgs::SecurityCenter::SecretScanningOrgQueriesHelper
  include SecurityCampaigns::AlertResultsHelper

  before_action :login_required
  before_action :security_center_required
  before_action :security_campaigns_required

  skip_before_action :set_failbot_context

  private

  sig { params(number: Integer, include_draft: T.nilable(T::Boolean)).returns(T.nilable(SecurityCampaigns::SecurityCampaign)) }
  def find_security_campaign(number:, include_draft: false)
    campaigns = SecurityCampaigns::SecurityCampaign.includes(:user_manager_users, team_manager_teams: :organization)
    campaigns = campaigns.published unless include_draft
    campaigns = campaigns.filter_spam_for(current_user)
    campaign = campaigns.find_by(number:, organization: this_organization.id)
    return nil if campaign.nil?

    # Allow security managers/owners to access all campaigns
    return campaign if SecurityProduct::Permissions::OrgAuthz.new(this_organization, actor: current_user).can_manage_org_security_products?

    # Do not allow developers to access closed campaigns
    return nil if campaign.closed?

    if campaign.alert_type == "code_scanning"
      ## Fetching the campaign with a list of most recently updated repositories with a limit of 3000
      ## Preventing the user from accessing the campaign if they do not have access to any of the repositories in the campaign
      query_service = CodeScanning::AlertQueryService.for_organization(
        user: current_user,
        user_session: nil,
        organization: T.must(campaign.organization),
        security_campaign_ids: [T.must(campaign.id)],
        allowed_repository_ids: allowed_repo_ids_and_limit_exceeded&.first,
      )
      campaign_with_counts = SecurityCampaigns::CampaignWithCounts.load(security_campaigns: [campaign], query_service:).first
      return nil if campaign_with_counts.nil?

      ## Do not allow access to the campaign if the campaign has no alerts the user can see
      if campaign_with_counts.total_count.zero?
        GitHub.dogstats.increment("security_campaigns.campaign_repos_not_accessible")
        GitHub.logger.info("User does not have access to any of the repositories in the campaign",
          "code.function" => "find_security_campaign",
          "gh.org.id" => T.must(campaign.organization).id,
          "gh.user.id" => current_user.id,
          "gh.security_campaign_id" => campaign.id,
          "request.referrer" => request.referrer,
        )
        return nil
      end
    elsif campaign.alert_type == "secret_scanning"
      query_service = SecretScanning::AlertQueryService.for_organization(
        organization: T.must(campaign.organization),
        current_user:,
        user_session:,
        security_campaign_ids: [T.must(campaign.id)],
        allowed_repository_ids: allowed_repo_ids_for_secret_scanning
      )
      alerts, open_alert_count, closed_alert_count, response, request_error = query_service.get_alerts_with_response(
        per_page: 1
      )
      ## Do not allow access to the campaign if the campaign has no alerts the user can see
      if alerts.empty?
        GitHub.dogstats.increment("security_campaigns.campaign_repos_not_accessible")
        GitHub.logger.info("User does not have access to any of the repositories in the secret scanning campaign",
          "code.function" => "find_security_campaign",
          "gh.org.id" => T.must(campaign.organization).id,
          "gh.user.id" => current_user.id,
          "gh.security_campaign_id" => campaign.id,
          "request.referrer" => request.referrer,
        )
        return nil
      end
    end

    campaign
  end

  def security_campaigns_required
    render_404 unless SecurityCampaigns.enabled?(this_organization)
  end
end
