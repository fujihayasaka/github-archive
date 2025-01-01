# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::SecurityCampaignsCloseController < Orgs::SecurityCenter::AbstractSecurityCampaignsController
  include ApplicationController::VerifiedFetchDependency

  before_action :manage_security_products_permission_required

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "Orgs::SecurityCenter::SecurityCampaignsCloseController#update",
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

    return render status: 422, json: { message: "Campaign is already closed" } if campaign.closed?

    campaign.update!(closed_at: Time.now.utc)

    GlobalInstrumenter.instrument("security_campaigns.security_campaign_close", {
      actor: current_user,
      security_campaign: campaign,
    })

    flash[:notice] = "The campaign \"#{campaign.name}\" was successfully closed."

    render status: 200, json: { redirect: security_center_closed_security_campaigns_path }
  end
end
