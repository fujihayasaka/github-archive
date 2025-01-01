# typed: true
# frozen_string_literal: true

class Businesses::LicenseCountsController < Businesses::BusinessController
  include BusinessesHelper

  before_action :login_required
  before_action :business_owner_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: %i(show)

  def show
    case metric
    when "total_licenses_used"
      consumed_licenses = total_consumed_licenses_count
      total_licenses = total_purchased_licenses_count
    when "enterprise_licenses"
      consumed_licenses = consumed_enterprise_licenses_count
      total_licenses = purchased_enterprise_licenses_count
    when "visual_studio_subscriptions"
      consumed_licenses = consumed_volume_licenses_count
      total_licenses = purchased_volume_licenses_count
    when "standalone_copilot_licenses"
      consumed_licenses = consumed_copilot_licenses_count
    when "users_access_licenses_used"
      consumed_licenses = consumed_users_access_licenses_count
    when "pending_invitation_licenses_used"
      consumed_licenses = consumed_pending_invitation_licenses_count
    end

    respond_to do |format|
      format.html do
        if consumed_licenses
          render Businesses::LicenseCountComponent.new(
            business:          current_business,
            consumed_licenses: consumed_licenses,
            total_licenses:    total_licenses,
          ), layout: false
        else
          render html: "", status: :not_found
        end
      end
    end
  end

  private

  def metric
    params[:metric]
  end
end
