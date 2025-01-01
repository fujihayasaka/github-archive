# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::SecurityCampaignsReopenController < Orgs::SecurityCenter::AbstractSecurityCampaignsController
  include ApplicationController::VerifiedFetchDependency

  before_action :manage_security_products_permission_required

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "Orgs::SecurityCenter::SecurityCampaignsReopenController#update",
  ].freeze, T::Array[String])

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Notify,
    ApplicationRecord::NotificationsEntries,
    only: [:update]

  depends_on_clusters \
    ApplicationRecord::Copilot,
    ApplicationRecord::SecurityOverviewAnalytics,
    only: [:update],
    optional: true

  allow_verified_fetch only: [:update]

  def update
    campaign = SecurityCampaigns::SecurityCampaign.find_by(number: params[:number], organization: this_organization.id)
    return render_404 if campaign.nil?

    return render status: 422, json: { message: "Campaign is already open" } if campaign.open?

    SecurityCampaigns::SecurityCampaign.transaction do
      # Reopen the campaign
      campaign.update!(closed_at: nil)

      # Ensure we're not exceeding the maximum number of campaigns
      if SecurityCampaigns::SecurityCampaign.lock.open.where(organization: this_organization).count > SecurityCampaigns::MAX_CAMPAIGNS_COUNT
        raise ActiveRecord::Rollback, SecurityCampaigns::MAX_CAMPAIGNS_REOPEN_ERROR_MESSAGE
      end
    rescue ActiveRecord::Deadlocked => e
      # Two concurrent transactions could look at the counts at the same time. If
      # this happens a deadlock will be noticed and one will be rolled back and the other will succeed.
      GitHub.dogstats.increment("security_campaigns.security_campaign_reopen", tags: ["kind:deadlock"])
      raise ActiveRecord::RecordNotSaved, SecurityCampaigns::CAMPAIGNS_CONCURRENT_REOPEN_MESSAGE
    end

    raise ActiveRecord::RecordNotSaved, SecurityCampaigns::MAX_CAMPAIGNS_REOPEN_ERROR_MESSAGE if campaign.reload.closed?

    GlobalInstrumenter.instrument("security_campaigns.security_campaign_reopen", {
      actor: current_user,
      security_campaign: campaign,
    })

    flash[:notice] = "The campaign \"#{campaign.name}\" was successfully re-opened."

    render status: 200, json: { redirect: security_center_security_campaign_path(number: campaign.number) }

    rescue ActiveRecord::RecordNotSaved => e
      GitHub.dogstats.increment("security_campaigns.security_campaign_reopen", tags: ["kind:rollback"])
      render status: 400, json: { message: e.message }
  end
end
