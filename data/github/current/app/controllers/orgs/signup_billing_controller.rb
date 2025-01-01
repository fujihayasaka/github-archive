# typed: true
# frozen_string_literal: true

class Orgs::SignupBillingController < ApplicationController
  include BillingSettingsHelper
  include OrganizationsHelper
  include OrganizationsControllerMethods
  include BusinessesHelper
  include SeatsHelper
  include SignupHelper
  include TradeControlsControllerMethods

  before_action :login_required
  before_action do
    T.bind(self, Orgs::SignupBillingController)
    check_trade_compliance(redirect_url: settings_organizations_url)
  end
  before_action :disable_color_modes
  before_action :require_signup_flow_redesign
  after_action :customer_category_instrumentation

  include Site::MicrosoftAnalyticsDependency
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
    ApplicationRecord::Configurations,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot, only: [:show], optional: true

  javascript_bundle "signup"
  javascript_bundle "organizations"
  javascript_bundle "billing"

  stylesheet_bundle "site"
  stylesheet_bundle :signup

  def show
    coupon = Coupon.find_by_code(params[:coupon]) if params[:coupon]

    if coupon && coupon.plan
      plan = coupon.plan
    else
      plan = GitHub::Plan.find(org_hash[:plan]) || GitHub::Plan.business
    end

    @current_organization = Organization.new(
      plan: plan.name,
      coupon: coupon,
      login: org_hash[:login],
      billing_email: org_hash[:billing_email].presence || params[:billing_email],
      company_name: org_hash[:company_name],
      plan_duration: User::BillingDependency::YEARLY_PLAN,
    )

    if GitHub.billing_enabled?
      per_seat_pricing_model = per_seat_pricing_model(coupon: coupon)

      # NB: If you are on a 100% off coupon the business plan could be
      # a default plan option. However, we also don't want to set it
      # if the coupon has a specific plan already associated.
      #
      # see https://github.com/github/github/commit/67d6809b7fd0219cccf8ddc646eb466da12bef28
      if per_seat_pricing_model.final_price.zero? && !coupon.try(:plan_specific?)
        plan = GitHub::Plan.business
      end

    end

    # The associated record built below is just used to build the form behavior on the UI.
    # The record is not saved in the DB. The logic for saving the associated record can be found
    # in Organization::Creator.
    account_screening_profile = if account_screening_profile_hash.present?
      @current_organization.build_trade_screening_record(account_screening_profile_hash)
    else
      nil
    end

    view = Orgs::CreationView.new({
      per_seat_pricing_model: per_seat_pricing_model,
      coupon: coupon,
      organization: @current_organization,
      plan: plan,
      terms_of_service: params[:terms_of_service_type] || "standard",
      org_transform: org_transform?,
      current_user: current_user,
      account_screening_profile: account_screening_profile
    })

    if params[:ref_page] == "/move_work/organization/plans"
      render "move_work/organizations/billing", locals: {
        progressbar_value: 50,
        view: view,
        current_context: current_user
      }
    else
      instrument_billing_form_loaded(flow: "ORGANIZATION_SIGNUP")
      render "organizations/signup/billing", locals: { view: view }
    end
  end

  private

  memoize def target
    current_organization
  end
end
