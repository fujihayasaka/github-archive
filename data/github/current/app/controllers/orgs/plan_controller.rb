# typed: true
# frozen_string_literal: true

class Orgs::PlanController < ApplicationController
  include BillingSettingsHelper
  include OrganizationsHelper
  include OrganizationsControllerMethods
  include SeatsHelper
  include SignupHelper
  include MarketingMethods
  include ApplicationHelper
  include Site::MicrosoftAnalyticsDependency

  before_action :login_required
  before_action :disable_color_modes
  before_action :org_creators_only
  before_action :require_signup_flow_redesign
  after_action :customer_category_instrumentation
  before_action :allow_initial_cookie_consent
  before_action :enable_microsoft_analytics
  before_action :add_microsoft_analytics_csp_exceptions
  layout "enterprise_funnel"

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot, only: [:show], optional: true

  javascript_bundle "signup"
  javascript_bundle "organizations"
  javascript_bundle "pricing"

  stylesheet_bundle "site"
  stylesheet_bundle "pricing"
  stylesheet_bundle :signup

  def show
    if [GitHub::Plan.business.name, GitHub::Plan.business_plus.name].include?(params[:plan])
      redirect_args = { redirect_params: { plan: params[:plan], coupon: params[:coupon] } }
      redirect_to(new_organization_path(plan: params[:plan], coupon: params[:coupon]))
    else
      render "organizations/signup/plan"
    end
  end
end
