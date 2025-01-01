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

    return render status: 422, json: { message: "Campaign is in draft" } if campaign.draft?
    return render status: 422, json: { message: "Campaign is already open" } if campaign.open?

    SecurityCampaigns::ReopeningService.call(campaign:, org: this_organization, actor: T.must(current_user))

    flash[:notice] = "The campaign \"#{campaign.name}\" was successfully re-opened."

    render status: 200, json: {}

    rescue ActiveRecord::RecordNotSaved => e
      render status: 400, json: { message: e.message }
  end
end
