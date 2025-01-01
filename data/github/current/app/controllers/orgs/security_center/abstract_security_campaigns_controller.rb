# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::AbstractSecurityCampaignsController < Orgs::SecurityCenter::AbstractSecurityCenterController
  include Orgs::SecurityCenter::CodeScanningOrgQueriesHelper

  before_action :login_required
  before_action :security_center_required
  before_action :security_campaigns_required

  skip_before_action :set_failbot_context

  private

  sig { params(number: Integer, include_draft: T.nilable(T::Boolean)).returns(T.nilable(SecurityCampaigns::SecurityCampaign)) }
  def find_security_campaign(number:, include_draft: false)
    scope = SecurityCampaigns::SecurityCampaign.includes(:user_manager_users, team_manager_teams: :organization)
    scope = scope.published unless include_draft
    campaign = scope.find_by(number:, organization: this_organization.id)
    return nil if campaign.nil?

    # Allow security managers/owners to access all campaigns
    return campaign if SecurityProduct::Permissions::OrgAuthz.new(this_organization, actor: current_user).can_manage_security_products?

    # Do not allow developers to access closed campaigns
    return nil if campaign.closed?

    ## Fetching the campaign with a list of most recently updated repositories with a limit of 3000
    ## Preventing the user from accessing the campaign if they do not have access to any of the repositories in the campaign
    query_service = CodeScanning::AlertQueryService.for_organization(
      user: current_user,
      user_session: nil,
      organization: T.must(campaign.organization),
      security_campaign_ids: [T.must(campaign.id)],
      allowed_repository_ids: allowed_repo_ids_and_limit_exceeded&.first,
    )
    campaign_with_counts = SecurityCampaigns::CampaignWithCounts.load(security_campaigns: [campaign], query_service:, user: current_user).first
    return nil if campaign_with_counts.nil?

    ## Do not allow access to the campaign if the campaign has no alerts
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

    campaign
  end

  def security_campaigns_required
    render_404 unless SecurityCampaigns.enabled?(this_organization)
  end
end
