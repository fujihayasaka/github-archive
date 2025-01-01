# typed: true
# frozen_string_literal: true

class Orgs::EnterprisePlanController < ApplicationController
  include OrganizationsHelper
  include OrganizationsControllerMethods
  include SignupHelper
  include MarketingMethods
  include Site::MicrosoftAnalyticsDependency

  before_action :dotcom_required
  before_action :ensure_not_multitenant_enterprise
  after_action :customer_category_instrumentation

  before_action :allow_initial_cookie_consent
  before_action :enable_microsoft_analytics
  before_action :add_microsoft_analytics_csp_exceptions
  layout "enterprise_funnel"

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot, only: [:show], optional: true

  javascript_bundle "signup"
  javascript_bundle "organizations"

  stylesheet_bundle "site"
  stylesheet_bundle "pricing"

  def show
    return redirect_to enterprise_trial_start_page_path if current_user

    default_org = Organization.new(plan: GitHub::Plan.default_plan)
    business_plus_pricing_model = Billing::PlanChange::PerSeatPricingModel.new(
      default_org,
      seats: default_org.seats,
      new_plan: GitHub::Plan.business_plus,
    )
    local_variables = {
      business_plus_pricing_model: business_plus_pricing_model
    }
    local_variables.merge(move_work: true) if params[:move_work].present?

    render "organizations/signup/enterprise_plan",  **local_variables
  end

  private

  def ensure_not_multitenant_enterprise
    render_404 if GitHub.multi_tenant_enterprise?
  end
end
