# typed: strict
# frozen_string_literal: true

class Copilot::Purchase::PlanPurchaseController < ApplicationController
  helper Copilot::Purchase::Helpers

  include Site::PreserveTrackingParamsDependency
  include Site::MicrosoftAnalyticsDependency

  before_action :login_required
  before_action :dotcom_required

  before_action only: :update do
    T.bind(self, Copilot::Purchase::PlanPurchaseController)
    check_trade_compliance(target: selected_account, sdn_redirect: true) if selected_account
  end

  before_action only: [:new, :index] do
    T.bind(self, Copilot::Purchase::PlanPurchaseController)
    check_trade_compliance(target: selected_account) if selected_account
  end

  before_action :allow_initial_cookie_consent, except: :index
  before_action :enable_microsoft_analytics, except: :index
  before_action :add_microsoft_analytics_csp_exceptions, except: :index
  before_action :redirect_restricted_standalone_org, only: [:update]
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
    ApplicationRecord::Ballast, only: [:new, :index]

  javascript_bundle :copilot
  javascript_bundle :billing
  global_navigation_title "Checkout", only: [:new]

  sig { void }
  def new
    return unless ensure_adminable_copilot_accounts

    account = T.must_because(selected_account) { "we return early if selected_account is nil" }

    if account.is_a?(::Business) && Copilot::Business.new(account).copilot_enablement_blocked?
      flash[:error] = Copilot::COPILOT_ENABLEMENT_TEMP_BLOCKED_MESSAGE
      redirect_to enterprise_licensing_path(account)
      return
    end

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
      account_eligibility: eligibility,
      selected_account: selected_account,
    }
  end

  sig { void }
  def index
    render(
      "copilot/purchase/index",
      locals: { selected_account: selected_account, accounts: adminable_accounts.to_a },
      layout: false
    )
  end

  sig { void }
  def update
    # Make sure the user can administer the account for which they're attempting to enable Copilot.
    # If they cannot, serve the error page.
    return unless ensure_adminable_copilot_accounts

    account = T.must_because(selected_account) { "we return early if selected_account is nil" }

    if account.is_a?(::Business) && Copilot::Business.new(account).copilot_enablement_blocked?
      flash[:error] = Copilot::COPILOT_ENABLEMENT_TEMP_BLOCKED_MESSAGE
      redirect_to enterprise_licensing_path(account)
      return
    end

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

      flash[:notice] = "GitHub Copilot was successfully enabled for #{account.slug}. You can now manage access and customize Copilot plans for organizations."
      if helpers.show_ai_controls?(account)
        redirect_to copilot_enterprise_ai_controls_enterprise_path(account)
      else
        redirect_to settings_copilot_enterprise_path(account)
      end
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
  memoize def selected_account
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
    if params[:organization].present?
      find_adminable_organization(params[:organization])
    else
      first_adminable_organization
    end
  end

  sig { returns(T.nilable(::Business)) }
  memoize def this_enterprise
    if params[:enterprise].present?
      adminable_businesses_scope.find_by(slug: params[:enterprise])
    else
      adminable_businesses_scope.first
    end
  end

  sig { params(login: String).returns(T.nilable(::Organization)) }
  def find_adminable_organization(login)
    org = Organization.find_by_login(login)
    return org if org&.adminable_by?(current_user)

    nil
  end

  sig { returns(T.nilable(::Organization)) }
  memoize def first_adminable_organization
    org_id = Ability.where(
      actor_id: current_user.id,
      actor_type: "User",
      subject_type: "Organization",
      action: Ability.actions[:admin],
    ).order(:subject_id).limit(1).pluck(:subject_id).first

    return nil if org_id.nil?

    Organization.includes(
      :business,
      customer: [:plan_subscription, :billing_contact],
    ).find_by(id: org_id)
  end

  sig { returns(ActiveRecord::Relation) }
  memoize def adminable_businesses_scope
    current_user
      .businesses(membership_type: :admin)
      .includes(:enterprise_agreements, customer: [:plan_subscription, :billing_contact])
      .reorder(:slug)
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

  sig { params(account: T.any(::Organization, ::Business)).returns(T::Boolean) }
  def standalone_signup_restricted?(account)
    return false unless account.is_a?(::Organization)

    Copilot::Organization.new(account).standalone_signup_restricted?
  end

  sig { void }
  def redirect_restricted_standalone_org
    account = selected_account
    return if account.nil?

    if standalone_signup_restricted?(account)
      flash[:notice] = "New Copilot Business signups are currently paused for organizations on the Free or Team plans."
      redirect_to organization_settings_path(account)
    end
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
end
