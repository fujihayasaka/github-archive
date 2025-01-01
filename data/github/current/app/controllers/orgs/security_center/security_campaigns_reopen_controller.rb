# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::SecurityCampaignsReopenController < Orgs::SecurityCenter::AbstractSecurityCampaignsController
  extend T::Sig

  include ApplicationController::VerifiedFetchDependency

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
    return render_404 unless current_user.feature_enabled?(:security_campaigns_closed)

    campaign = SecurityCampaigns::SecurityCampaign.find_by(number: params[:number], organization: this_organization.id)
    return render_404 if campaign.nil?

    return render status: 422, json: { message: "Campaign is already open" } if campaign.open?

    campaign.update!(closed_at: nil)

    flash[:notice] = "The campaign \"#{campaign.name}\" was successfully re-opened."

    render status: 200, json: { redirect: security_center_security_campaign_path(number: campaign.number) }
  end
end
