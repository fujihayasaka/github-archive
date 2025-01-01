# typed: strict
# frozen_string_literal: true

class Copilot::Purchase::PlanPurchaseController < ApplicationController
  include Site::PreserveTrackingParamsDependency
  include Site::MicrosoftAnalyticsDependency

  before_action :login_required
  before_action :dotcom_required
  before_action :add_paypal_csp_exceptions, only: :new

  before_action only: :update do
    T.bind(self, Copilot::Purchase::PlanPurchaseController)
    check_trade_compliance(target: selected_account, sdn_redirect: true) if selected_account
  end

  before_action only: :new do
    T.bind(self, Copilot::Purchase::PlanPurchaseController)
    check_trade_compliance(target: selected_account) if selected_account
  end

  before_action :allow_initial_cookie_consent
  before_action :enable_microsoft_analytics
  before_action :add_microsoft_analytics_csp_exceptions
  before_action :dismiss_propensity_nudge, only: :new

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Ballast, only: [:new]

  javascript_bundle :copilot
  javascript_bundle :billing

  sig { void }
  def new
    context_region_title("Checkout")

    return unless ensure_adminable_copilot_accounts

    account = T.must_because(selected_account) { "we return early if selected_account is nil" }

    eligibility = Copilot::Purchase::Eligibility.for(
      account: account
    )

    potential_ineligibility_reason = eligibility[:reason] == :ok ? nil : eligibility[:reason]
    log_request(
      "Copilot purchase started",
      "http.request.header.referrer" => request.referrer,
      "gh.copilot.purchase.ineligible_reason" => potential_ineligibility_reason
    )
    increment_dogstats("copilot.checkout.started", failure_reason: potential_ineligibility_reason)

    render "copilot/purchase/new", layout: "copilot_plan_purchase", locals: {
      accounts: adminable_accounts.to_a,
      account_eligibility: eligibility,
      selected_account: selected_account,
    }
  end

  sig { void }
  def update
    # Make sure the user can administer the account for which they're attempting to enable Copilot.
    # If they cannot, serve the error page.
    return unless ensure_adminable_copilot_accounts

    account = T.must_because(selected_account) { "we return early if selected_account is nil" }

    # here we need to check the eligibility of the account again, just in case
    eligibility = Copilot::Purchase::Eligibility.for(
      account: account
    )

    unless Copilot::Purchase::Eligibility.eligible?(factor: eligibility)
      log_request("Copilot purchase failure", "gh.copilot.purchase.ineligible_reason" => eligibility[:reason])
      increment_dogstats("copilot.checkout.failure", failure_reason: eligibility[:reason])

      reason_msg = Copilot::Purchase::Eligibility::INELIGIBLE_REASON_MESSAGES[eligibility[:reason]]
      flash[:error] = "We couldn’t enable Copilot for this account because it #{reason_msg}. Please contact GitHub support."

      account_type = account.is_a?(::Organization) ? :organization : :enterprise
      redirect_to_with_utm copilot_plan_purchase_path, account_type => account
      return
    end

    if account.is_a? ::Business
      # do we need to return an error here if there is somehow not a customer?
      customer = T.must_because(account.customer) { "we've already determined billing eligibility" }

      CopilotEnterpriseMailer.welcome_business_admins(account).deliver_later
      Copilot::Business.new(account).disable_copilot!

      # The ineligibility reason should always be :ok if we got here.
      # Logging it excplicitly in case it isn't.
      log_request(
        "Copilot purchase succeeded",
        "gh.copilot.purchase.ineligible_reason" => eligibility[:reason]
      )
      increment_dogstats("copilot.checkout.success")
      onboard_copilot_to_billing_platform(account)

      flash[:notice] = "GitHub Copilot was successfully enabled for #{account.slug}. You can now manage access and customize Copilot plans for organizations."
      redirect_to settings_copilot_enterprise_path(account)
    else
      copilot_organization = Copilot::Organization.new(account)
      copilot_organization.ensure_signup(actor: current_user, url: staff_url_for(account)) do |success|
        if success
          copilot_organization.enable_copilot!

          # Only standalone orgs can go through the new flow, so the assignment of a business plan should be safe
          # We don't need to send emails through the method below because:
          #   a. there wont be any existing users
          #   b. we need to send an extra param to the org admin
          copilot_organization.copilot_plan_business!(false)
          CopilotForBusinessMailer.welcome_org_admins(account, is_new_signup: true).deliver_later

          log_request(
            "Copilot purchase succeeded",
            "gh.copilot.plan" => "business",
            "gh.copilot.purchase.ineligible_reason" => eligibility[:reason]
          )
          increment_dogstats("copilot.checkout.success")
          onboard_copilot_to_billing_platform(account)

          flash[:notice] = "GitHub Copilot was successfully enabled for #{account.display_login}. You can now manage access and Copilot policies for your organization."
          redirect_to settings_org_copilot_seat_management_path(account)
        else
          log_request(
            "Copilot purchase failure",
            "gh.copilot.purchase.ineligible_reason" => "unknown",
          )
          increment_dogstats("copilot.checkout.failure", failure_reason: "unknown")

          flash[:error] = "We couldn’t enable Copilot for this account. Please contact GitHub support."
          redirect_to_with_utm copilot_plan_purchase_path, organization: account
        end
      end
    end
  end

  private

  sig { returns(T::Boolean) }
  def ensure_adminable_copilot_accounts
    if selected_account.nil?
      log_request("No eligible accounts for Copilot purchase")
      increment_dogstats("copilot.checkout.failure", failure_reason: "no_eligible_accounts")

      render "copilot/purchase/no_eligible_accounts_error", layout: "copilot_plan_purchase"
      return false
    end

    true
  end

  sig { returns(T.any(T.nilable(::Organization), T.nilable(::Business))) }
  def selected_account
    org = this_organization if params[:organization].present? || prioritize_org?

    # The user might not have any orgs, but that doesn't mean they can't click the
    # Copilot for Business link and proceed through the flow with one of their enterprises.
    return org if org.present?
    return this_enterprise if params[:enterprise].present? || prioritize_biz?

    this_enterprise || this_organization
  end

  sig { returns(Copilot::Payloads::AdminableAccounts) }
  memoize def adminable_accounts
    Copilot::Payloads::AdminableAccounts.new(current_user)
  end

  sig { returns(T.nilable(::Organization)) }
  memoize def this_organization
    org = if params[:organization]
      found = adminable_accounts.adminable_orgs.find { |org| params[:organization] == org.display_login }
    else
      adminable_accounts.adminable_orgs.first
    end

    org
  end

  sig { returns(T.nilable(::Business)) }
  memoize def this_enterprise
    businesses = adminable_accounts.adminable_businesses

    return businesses.find_by(slug: params[:enterprise]) if params[:enterprise].present?

    businesses.first
  end

  sig { returns(T.any(User, Symbol)) }
  def target_for_conditional_access
    logged_in? ? current_user : :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  sig { returns(T.any(User, Symbol)) }
  def resource_for_conditional_access
    # cap_bypass:to_fix - this controller is also targeting Business or Organization and should be considered in those actions
    logged_in? ? current_user : :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  sig { returns(T::Boolean) }
  def prioritize_org?
    params[:priority] == "business"
  end

  sig { returns(T::Boolean) }
  def prioritize_biz?
    params[:priority] == "enterprise"
  end

  sig { params(account: ::Organization).returns(String) }
  def staff_url_for(account)
    stafftools_user_copilot_settings_url(account, { host: GitHub.admin_host_name, protocol: "https" })
  end

  sig { void }
  def add_paypal_csp_exceptions
    paypal_csp_exceptions = {
      img_src: [GitHub.paypal_checkout_url],
      connect_src: [GitHub.braintreegateway_url, GitHub.braintree_analytics_url]
    }
    SecureHeaders.append_content_security_policy_directives(request, paypal_csp_exceptions)
  end

  sig { returns(String) }
  def account_type
    selected_account&.class&.name&.downcase || "unknown"
  end

  sig { params(message: String, extra: T::Hash[String, T.any(String, Integer)]).void }
  def log_request(message, extra = {})
    GitHub.logger.info(
      message,
      {
        "rails.controller.name" => controller_name,
        "rails.controller_action" => action_name,
        "gh.actor.id" => current_user.id,
        "gh.copilot.configurable_object.type" => account_type,
        "gh.copilot.configurable_object.id" => selected_account&.id,
      }.merge(extra)
    )
  end

  sig { params(metric: String, failure_reason: T.nilable(T.any(String, Symbol))).void }
  def increment_dogstats(metric, failure_reason: nil)
    tags = ["account_type:#{account_type}"]
    tags << "failure_reason:#{failure_reason}" if failure_reason.present?

    GitHub.dogstats.increment(metric, tags: tags)
  end

  sig { params(to_path: String, additional_params: T::Hash[String, String]).void }
  def redirect_to_with_utm(to_path, additional_params = {})
    redirect_to preserve_utm_query_params(to_path, additional_params)
  end

  sig { params(to_path: String, additional_params: T::Hash[String, String]).returns(String) }
  def preserve_utm_query_params(to_path, additional_params = {})
    params = (utm_memo).merge(additional_params)
    return to_path if params.empty?

    uri = URI::HTTP.build(path: to_path, query: params.to_query)
    # only return the absolute path and query, don't include blank hostname and protocol
    "#{uri.path}?#{uri.query}"
  end

  sig { returns(T::Hash[String, String]) }
  def utm_memo
    session[:utm_memo] || {}
  end

  sig { void }
  def dismiss_propensity_nudge
    return unless params[:ref] == "dashboard_nudge" && current_user.feature_flag_enabled?(:copilot_business_propensity_nudge, default: false)

    ActiveRecord::Base.connected_to(role: :writing) do
      current_user.dismiss_notice("dashboard_promo_copilot_business_propensity_nudge")
    end
  end

  sig { params(account: T.any(::Organization, ::Business)).void }
  def onboard_copilot_to_billing_platform(account)
    if !account.billed_via_billing_platform?
      account.customer&.set_metered_plan_and_onboard_to_all_billing_platform_products
      increment_dogstats("copilotbusiness.onboard_to_billing_platform")
    end

    account.customer&.onboard_copilot_premium_request_zero_dollar_budget unless account.feature_flag_enabled?(:billing_platform_overages_policies_enabled, default: false)
  end
end
