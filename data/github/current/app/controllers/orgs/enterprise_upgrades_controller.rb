# typed: true
# frozen_string_literal: true

class Orgs::EnterpriseUpgradesController < ApplicationController
  include OrganizationsHelper

  before_action :login_required
  before_action :dotcom_required
  before_action :org_admins_only
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :eligible_for_upgrade_to_enterprise

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Ballast,
    ApplicationRecord::Copilot,
    ApplicationRecord::Repositories,
    only: %i(new)

  javascript_bundle :organizations

  def new
    suggested_slug = Business.unique_slug(current_organization.display_login)
    render "settings/organization/new_upgrade_to_enterprise", locals: { business: Business.new, suggested_upgrade_slug: suggested_slug }
  end

  def create
    if params[:gca_business].blank?
      flash[:error] = "You must accept the GitHub Customer Agreement to continue."
      return redirect_to new_org_enterprise_upgrade_path(current_organization)
    end

    business_creator = current_organization.perform_direct_upgrade_to_enterprise(
      params,
      current_user,
      forced_upgrade: false,
      )

    if business_creator.error_message.nil?
      business = business_creator.business
      flash[:notice] = "Created #{business.name}."
      redirect_to enterprise_path(business)
    else
      flash[:error] = "Failed to create enterprise account: #{business_creator.error_message}."
      render "settings/organization/new_upgrade_to_enterprise", status: 422, locals: {
        business: business_creator.business,
        business_params: business_params,
        suggested_upgrade_slug: ""
      }
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

  def eligible_for_upgrade_to_enterprise
    render_404 unless current_organization.eligible_for_upgrade_to_enterprise?
  end
end
