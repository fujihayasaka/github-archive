# typed: true
# frozen_string_literal: true

class Orgs::SeatsController < ApplicationController
  include BillingSettingsHelper
  include OrganizationsHelper
  include OrganizationsControllerMethods
  include BusinessesHelper
  include SeatsHelper

  include ApplicationController::JsonDependency

  before_action :login_required
  before_action :org_creators_only
  before_action do
    T.bind(self, Orgs::SeatsController)
    check_trade_compliance(target: current_organization)
  end
  after_action :customer_category_instrumentation

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    only: [:show]

  def show
    @current_organization = if params[:organization].present?
      Organization.new(login: org_hash[:login], company_name: org_hash[:company_name])
    else
      Organization.new
    end
    @coupon = Coupon.find_by_code(params[:coupon])
    new_org_url_options = {
      coupon: @coupon,
      plan_duration: params[:plan_duration],
      plan: params[:new_plan],
      ref_page: params[:ref_page],
      terms_of_service_type: params[:terms_of_service_type] || "standard",
      agreed_to_terms: params[:agreed_to_terms],
      organization: {
        login: @current_organization.display_login,
        profile_name: @current_organization.name,
        company_name: @current_organization.company_name,
      },
    }

    if params[:transform_user].present?
      new_org_url_options[:transform_user] = "1"
    end

    data = hash_for_pricing_model_change(
      per_seat_pricing_model(coupon: @coupon, new_plan: params[:new_plan]),
      org_signup_billing_url(new_org_url_options),
    )

    data[:is_enterprise_cloud_trial] = params[:new_plan] == GitHub::Plan.business_plus.name

    respond_to do |format|
      format.json do
        render json: data
      end
    end
  end
end
