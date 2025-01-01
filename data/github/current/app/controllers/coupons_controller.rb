# typed: strict
# frozen_string_literal: true
class CouponsController < ApplicationController
  extend T::Sig

  include BillingSettingsHelper
  include OrganizationsHelper
  include TradeControlsControllerMethods

  before_action :find_coupon
  before_action :set_selected_account, if: :logged_in?
  before_action :login_required, only: [:redeem]
  before_action :redemption_trade_controls_restrictions, only: [:redeem]
  before_action :add_csp_exceptions, only: [:show]

  before_action except: :redeem do
    T.bind(self, CouponsController)

    if logged_in?
      check_trade_compliance(target: target)
    end
  end

  before_action only: :redeem do
    T.bind(self, CouponsController)

    check_trade_compliance(target: target, sdn_redirect: true)
  end

  before_action :business_plus_only_required, only: [:show_business_plus_only]

  sig { returns(T.nilable(Billing::Types::Account)) }
  attr_reader :selected_account

  sig { returns(T.nilable(Coupon)) }
  attr_reader :coupon

  javascript_bundle :signup
  javascript_bundle :billing, only: [:show, :show_business_plus_only, :redeem]
  stylesheet_bundle :signup

  # The following actions do not require conditional access checks because
  # they *don't* access protected organization resources.
  # rubocop:disable GitHub/DoNotSkipCapBeforeAction
  skip_before_action :perform_conditional_access_checks, only: %w(
    find
    show
    show_business_plus_only
  )

  include GitHub::RateLimitedRequest
  rate_limit_requests \
    only: [:show, :redeem],
    key: :coupon_rate_limit_key,
    max: 1000,
    ttl: 1.hour,
    stealthy: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:business_try]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  CSP_EXCEPTIONS = T.let({
    img_src: [GitHub.paypal_checkout_url].freeze,
    connect_src: [GitHub.braintreegateway_url, GitHub.braintree_analytics_url].freeze,
  }.freeze, T::Hash[Symbol, T::Array[String]])

  sig { void }
  def find # rubocop:todo GitHub/UseRestfulActions
    flash.keep if flash[:error]
    render "coupons/find"
  end

  sig { void }
  def show
    if @coupon
      @plan = @coupon.try(:plan) || GitHub::Plan.default_plan
      override_analytics_location(request.path.sub(@coupon.code, "<coupon-code>"))

      if @coupon.business_plus_only_coupon?
        if logged_in? && @coupon.eligible_accounts(current_user).empty?
          redirect_to new_organization_path(coupon: @coupon.code)
        else
          show_business_plus_only
        end
      elsif @coupon.self_serve_business_plus_coupon? && current_user.can_apply_coupon_to_self_serve_enterprise_account?
        if logged_in? && @coupon.eligible_accounts(current_user).empty?
          # If the user has no owned EAs then prompt them to create a new one
          redirect_to new_enterprise_from_coupon_path(code: @coupon.code)
        else
          # If the user has an EA, then move them to the page showing them all their EAs
          show_businesses_only
        end
      elsif @coupon.org_only? && user_has_no_organizations?
        redirect_to new_organization_path(coupon: @coupon.code)
      elsif logged_in? && !@coupon.redeemable_by?(current_user)
        flash[:error] = "This coupon can't be redeemed with your account. Please contact support."
        redirect_to find_coupon_url
      else
        @selected_plan = GitHub::Plan.find(params[:plan])
        instrument_billing_form_loaded(flow: "COUPONS") if logged_in?
        render "coupons/show"
      end
    else
      check_rate_limit(stealthy: false)
      return if performed?

      if Coupon.valid_code? params[:code]
        flash[:error] = "Sorry, we couldn’t find a coupon with the code: #{params[:code]}"
      else
        flash[:error] = "Sorry, we couldn’t find a coupon with that code"
      end
      redirect_to find_coupon_url
    end
  end

  sig { void }
  def business_try # rubocop:todo GitHub/UseRestfulActions
    unless params[:code].present?
      return render_404
    end
    redirect_to redeem_coupon_url(params[:code])
  end

  sig { void }
  def redeem # rubocop:todo GitHub/UseRestfulActions
    @selected_plan = T.let(GitHub::Plan.find(params[:plan]), T.nilable(GitHub::Plan))
    coupon = self.coupon
    selected_account = self.selected_account

    if selected_account && coupon
      details = payment_details.merge(actor: current_user, plan: @selected_plan)
      if selected_account.is_a?(Business)
        result = selected_account.schedule_async_coupon_payment_collection(coupon, current_user)
      else
        result = GitHub::Billing.redeem_coupon_and_charge(selected_account, coupon, details)
      end

      if result.success?
        instrument_billing_form_submitted(flow: "COUPONS")
        flash[:notice] = "You have successfully redeemed your coupon for #{selected_account.display_login}."

        if params[:return_to]
          safe_redirect_to params[:return_to]
        elsif selected_account.organization?
          redirect_to org_dashboard_path(selected_account)
        elsif selected_account.is_a?(Business)
          redirect_to enterprise_path(selected_account)
        else
          redirect_to "/"
        end
      else
        flash[:error] = result.error_message
        if params[:return_to]
          safe_redirect_to params[:return_to]
        else
          render "coupons/show"
        end
      end
    else
      check_rate_limit(stealthy: false)
      render_404 unless performed?
    end
  end

  sig { void }
  def show_business_plus_only # rubocop:todo GitHub/UseRestfulActions
    @plan = T.must(coupon).plan
    render "coupons/business_plus_only/show"
  end

  sig { void }
  def show_businesses_only # rubocop:todo GitHub/UseRestfulActions
    eligible_businesses = T.must(@coupon).eligible_accounts(current_user)
    if eligible_businesses.include?(selected_account)
      render "coupons/show"
    else
      redirect_to redeem_coupon_url(@coupon&.code, id: eligible_businesses.first&.display_login)
    end
  end

  private

  sig { returns(T::Boolean) }
  def user_has_no_organizations?
    logged_in? && current_user.owned_organizations.reject(&:invoiced?).empty?
  end

  sig { override.returns(::Billing::Types::Account) }
  def target
    selected_account.presence || current_user
  end

  sig { returns(String) }
  def coupon_rate_limit_key
    "coupon-redemption:#{request.remote_ip}"
  end

  sig { void }
  def find_coupon
    code = Coupon.clean_old_code(params[:code])
    @coupon = T.let(Coupon.find_by(code: code), T.nilable(Coupon))
    @coupon = nil if @coupon && @coupon.expired?
  end

  sig { returns(T.nilable(Billing::Types::Account)) }
  def set_selected_account
    @selected_account = T.let(
      if @coupon && @coupon.self_serve_business_plus_coupon? && current_user.can_apply_coupon_to_self_serve_enterprise_account?
        current_business = Business.find_by(slug: params[:id])
        current_business if current_business&.owners&.include?(current_user)
      elsif params[:id] == current_user.display_login
        current_user
      elsif current_organization && current_organization.adminable_by?(current_user)
        current_organization
      end, T.nilable(Billing::Types::Account)
    )
  end

  sig { void }
  def business_plus_only_required
    render_404 unless coupon&.business_plus_only_coupon?
  end

  sig { void }
  def redemption_trade_controls_restrictions
    selected_account = self.selected_account
    if selected_account&.has_any_trade_restrictions?
      if selected_account.organization?
        flash[:trade_controls_organization_billing_error] = true
        return redirect_to(org_root_path(selected_account))
      else
        flash[:trade_controls_user_billing_error] = true
        return redirect_to(billing_url)
      end
    end
    check_trade_compliance(target: target)
  end
end
