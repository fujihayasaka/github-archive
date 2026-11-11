# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::SelfServeOrganizationUpgradesController < Stafftools::Businesses::BusinessBaseController

  skip_before_action :business_required, only: %i(index)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: %i(index)

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    render "stafftools/businesses/self_serve_organization_upgrades_list", layout: "stafftools", locals: {
      businesses: businesses.paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE),
      filter: filter,
      query: params[:query],
    }
  end

  private

  def upgrade_params
    params.permit(:query, :active_page, :page, :tab,
      filter: [:owned_by, :created, :upgrade_state])
  end

  memoize def businesses
    businesses = Business.self_serve_organization_upgrading_or_upgraded.for_query(params[:query])
    return businesses if filter.empty?
    businesses = businesses.order(created_at: filter[:created].to_sym) if filter[:created].present?

    if filter[:upgrade_state].present?
      businesses = case filter[:upgrade_state]
      when "completed"
        businesses.where(
          trial_completion_status: [
            :no_trial_or_active_trial,
            :organization_upgrade_completed,
            :created_from_coupon,
          ])
      when "initiated"
        businesses.organization_upgrade_initiated
      when "in-progress"
        businesses.organization_upgrade_purchase_initiated
      when "direct-upgraded"
        businesses.organization_direct_upgraded
      when "initiated-from-coupon"
        businesses.creation_initiated_from_coupon
      when "coupon-purchase-initiated"
        businesses.creation_from_coupon_purchase_initiated
      when "created-from-coupon"
        businesses.created_from_coupon
      end
    end

    if filter[:owned_by].present?
      staff = filter[:owned_by] == "staff"
      businesses = T.must(businesses).is_staff_owned(staff)
    end
    businesses
  end

  memoize def filter
    filter = upgrade_params[:filter].to_h.presence || HashWithIndifferentAccess.new
  end
end
