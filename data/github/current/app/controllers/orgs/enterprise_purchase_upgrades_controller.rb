# typed: true
# frozen_string_literal: true

class Orgs::EnterprisePurchaseUpgradesController < ApplicationController
  include OrganizationsHelper

  before_action :login_required
  before_action :dotcom_required
  before_action :org_admins_only
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :eligible_for_purchase_upgrade_to_enterprise

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Ballast,
    ApplicationRecord::Copilot,
    only: %i(new)

  def new
    render "settings/organization/new_purchase_upgrade_to_enterprise", locals: { business: Business.new }
  end

  def create
    business_creator = Business::Creator.new(
      business_params: business_params.merge(
        can_self_serve: true,
        owners: [current_user],
        billing_email: current_organization.billing_email,
        seats: current_organization.default_seats,
        upgrade_initiated_from_organization_id: current_organization.id,
        customer_attributes: business_params.fetch(:customer_attributes, {}).merge(
          billing_type: "card"
        )),
      actor: current_user
    )

    if business_creator.valid?
      business_creator.save!
      business = business_creator.business
      business.enable_self_serve_payments(skip_billing: true)
      business.initiate_organization_upgrade(current_user)
      current_organization.upgrade_to_enterprise_in_progress!(business)
      # Delete the EA after 5 days if they have not completed the upgrade
      BusinessUpgradeCancellationJob.set(wait: 5.days).perform_later(business)
      BusinessMailer.organization_upgrade_pending(current_user, business).deliver_later(wait: 25.hours)

      redirect_to billing_upgrade_from_organization_enterprise_path(business)
    else
      flash[:error] = "Failed to create enterprise account: #{business_creator.error_message}."
      redirect_to :back
    end
  end

  private

  def business_params
    params.require(:business).permit(
      :name,
      :slug,
      :shortcode
    )
  end

  def eligible_for_purchase_upgrade_to_enterprise
    business = current_organization.upgrade_to_enterprise_in_progress
    return render_404 unless current_organization.eligible_for_purchase_upgrade_to_enterprise?(actor: current_user, skip_in_progress_check: business.present?)
    return redirect_to billing_upgrade_from_organization_enterprise_path(business) if business.present?
  end
end
