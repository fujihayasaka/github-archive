# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::SecurityCampaignRepositoriesSummaryController < Orgs::SecurityCenter::AbstractSecurityCampaignsController
  include ApplicationController::VerifiedFetchDependency
  include CodeScanning::AlertsSerializer

  before_action :organization_read_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Notify,
    only: [:index]

  allow_verified_fetch only: [:index]

  def index
    allowed_repository_ids = allowed_repo_ids_and_limit_exceeded&.first

    # If there are no repositories allowed, we don't show the campaign page anyway so the endpoint won't be called, this is just an extra check and also for Authz tests
    # If it's nil, it means the user can see all repositories.
    return render status: 404, json: { error: "Not Found" } if !allowed_repository_ids.nil? && allowed_repository_ids.empty?

    security_campaign = SecurityCampaigns::SecurityCampaign.find_by(number: params[:number], organization: this_organization)
    return render status: 404, json: { message: "Security campaign not found" } if security_campaign.nil? || security_campaign.hide_from_user?(current_user)

    return render status: 404, json: { message: "Security campaign is in draft" } if security_campaign.draft?

    query_service = CodeScanning::AlertQueryService.for_organization(
      user: current_user,
      user_session: user_session,
      organization: this_organization,
      allowed_repository_ids:,
      security_campaign_ids: [security_campaign.id],
    )
    begin
      campaign_with_counts = SecurityCampaigns::CampaignWithGroupedCounts.load(
        security_campaign:,
        user: current_user,
        query_service:,
        query_string: "",
        after_cursor: nil,
        before_cursor: nil,
        page_size: SecurityCampaigns::MAX_ALERTS_REPOSITORY_COUNT
      )
    rescue StandardError # rubocop:disable Lint/RescueException
      return render status: 500, json: { message: "Failed to fetch repositories for the campaign. Please reload and try again." }
    end

    repositories_payload = campaign_with_counts.groups.map do |group|
      {
        repository: serialized_repository(repository: T.must(group.repositories.first)),
        alertCount: group.open_count + group.closed_count,
      }
    end

    render json: {
      repositories: repositories_payload,
    }
  end
end
