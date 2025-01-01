# typed: strict
# frozen_string_literal: true

class Businesses::BillingSettingsController < Businesses::BusinessController
  include BillingSettingsHelper
  include TradeControlsControllerMethods
  T.unsafe(self).react_bundle_name = "billing-app"

  before_action :ensure_billing_enabled
  before_action :business_owner_required, only: :cancel_trial
  before_action :business_access_required, except: [:authenticate_azure]
  # Org admins need to be able to authenticate when modifying cost centers.
  before_action -> do
    T.bind(self, Businesses::BillingSettingsController)

    business_access_required(allow_org_owners: true)
  end, only: [:authenticate_azure]
  before_action :business_trial_required, only: [:cancel_trial, :cancel_addon_trial, :convert_trial]
  before_action :eligible_for_self_serve_payment_required, only: [
    :payment_history,
    :update_payment_information,
    :update_payment_method,
  ]

  before_action :trial_conversion_not_initiated_required, only: [:convert_trial]
  before_action :add_csp_exceptions, only: [:show]
  before_action only: [:update_payment_method, :convert_trial] do
    T.bind(self, Businesses::BillingSettingsController)
    check_trade_compliance(target: this_business, redirect_url: settings_billing_tab_enterprise_url(tab: :payment_information), sdn_redirect: true)
  end
  before_action only: [:show] do
    T.bind(self, Businesses::BillingSettingsController)
    check_trade_compliance(target: this_business, trade_controls_redirect: false)
  end

  skip_before_action :redirect_if_organization_upgrade_initiated, only: [:update_payment_information, :update_payment_method]
  skip_before_action :redirect_if_coupon_redemption_initiated, only: [:update_payment_information, :update_payment_method]

  include Site::MicrosoftAnalyticsDependency
  before_action :allow_initial_cookie_consent, only: [:show]
  before_action :enable_microsoft_analytics, only: [:show]
  before_action :add_microsoft_analytics_csp_exceptions, only: [:show]
  layout "enterprise_funnel", only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:payment_history]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:authenticate_azure]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:authenticate_azure],
    optional: true

  CSP_EXCEPTIONS = T.let({
    img_src: [GitHub.paypal_checkout_url].freeze,
    connect_src: [GitHub.braintreegateway_url, GitHub.braintree_analytics_url].freeze,
  }.freeze, T::Hash[Symbol, T::Array[String]])

  PER_PAGE = 10

  javascript_bundle "billing-settings"

  stylesheet_bundle :settings

  sig { void }
  def authenticate_azure # rubocop:todo GitHub/UseRestfulActions
    @code = T.let(params[:oauth_code], T.nilable(String))

    # This is true if we already sent the user to explicitly select a tenant
    explicit_tenant_selected = params[:explicit_tenant_selected] == "true"

    safe_redirect_to redirect_path(tab: :payment_information) if @code.nil?

    if @code
      client = Billing::Azure::BusinessSubscriptionClient.new(current_user, this_business)
      client.fetch_and_store_token(@code)

      tenants = client.fetch_tenants
      if !explicit_tenant_selected && !tenants.nil? && tenants.count > 1
        GitHub.dogstats.increment("azure.self_serve.showing_tenant_selection")

        path_settings = { show_subscriptions: true, anchor: "open_tenant_dialog" }
        unless this_business.billed_via_billing_platform?
          path_settings[:tab] = :payment_information
        end

        # Ask user to select a tenant first
        safe_redirect_to redirect_path(**path_settings)

      else
        GitHub.dogstats.increment("azure.self_serve.showing_subscription_selection")

        path_settings = { show_subscriptions: true, anchor: "open_dialog" }
        unless this_business.billed_via_billing_platform?
          path_settings[:tab] = :payment_information
        end

        safe_redirect_to redirect_path(**path_settings)
      end
    end
  rescue Faraday::Error => e
    Failbot.report(e)
    flash[:error] = "Failed to fetch authentication information from Azure. Please try again."
    if this_business.billed_via_billing_platform?
      redirect_to enterprise_billing_payment_information_path(this_business)
    else
      redirect_to settings_billing_tab_enterprise_path(this_business, tab: :payment_information)
    end

  end

  sig { void }
  def show
    if params[:tab] == "billing_emails" && this_business.disable_legacy_billing_page?
      return redirect_to enterprise_billing_contacts_path(this_business)
    end

    if params[:tab] == "payment_information" && !params[:show_subscriptions] && this_business.disable_legacy_billing_page?
      return redirect_to enterprise_billing_payment_information_path(this_business)
    end

    if params[:tab] == "marketplace_apps" && this_business.disable_legacy_billing_page?
      return redirect_to enterprise_billing_marketplace_apps_path(this_business)
    end

    if params[:tab] == "sponsorships" && this_business.disable_legacy_billing_page?
      return redirect_to enterprise_billing_sponsorships_path(this_business)
    end

    if params[:tab] == "payment_history" && this_business.disable_legacy_billing_page?
      return redirect_to enterprise_billing_payment_history_index_path(this_business)
    end

    if params[:tab] == "past_invoices" && this_business.disable_legacy_billing_page?
      return redirect_to enterprise_billing_past_invoices_path(this_business)
    end

    return redirect_to enterprise_billing_path(this_business) if this_business.disable_legacy_billing_page?

    if params[:org_plan_select].present?
      flash.now[:notice] = "Organization plans are not available for organizations that are billed at the enterprise level."
    end
    advanced_security_organizations_page = params[AdvancedSecurityEntitiesLinkRenderer::PAGE_PARAM].to_i
    advanced_security_organizations_page = 1 if advanced_security_organizations_page == 0
    advanced_security_users_page = params[AdvancedSecurityUsersLinkRenderer::PAGE_PARAM].to_i
    advanced_security_users_page = 1 if advanced_security_users_page == 0

    shared_storage_page = params[SharedStorageRenderer::PAGE_PARAM].to_i
    shared_storage_page = 1 if shared_storage_page == 0

    marketplace_apps_page = params[MarketplaceAppsLinkRenderer::PAGE_PARAM].to_i
    marketplace_apps_page = 1 if marketplace_apps_page == 0

    render "businesses/billing_settings/show",
           locals: {
             current_tab: params[:tab],
             advanced_security_organizations_page: advanced_security_organizations_page,
             advanced_security_users_page: advanced_security_users_page,
             shared_storage_page: shared_storage_page,
             marketplace_apps_page: marketplace_apps_page,
           }
  end

  sig { void }
  def update_members_can_make_purchases # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless this_business.can_self_serve?

    setting_value = members_can_make_purchases_params[:members_can_make_purchases]&.downcase&.to_s
    case setting_value
    when "enabled"
      this_business.allow_members_can_make_purchases(actor: current_user)
      flash[:notice] = "Organization admins can now make purchases."
    when "disabled"
      this_business.disallow_members_can_make_purchases(actor: current_user, force: true)
      flash[:notice] = "Organization admins can no longer make purchases."
    else
      flash[:error] = "You provided an invalid input value. Please try again."
    end
    redirect_back(fallback_location: settings_billing_enterprise_path(this_business))
  end

  sig { void }
  def cancel_trial # rubocop:todo GitHub/UseRestfulActions
    if params[:cancel_trial_confirmation].blank?
      cancelling_flavor = this_business.trial_expired? ? "deleting" : "cancelling"
      flash[:error] = "You must read and understand the consequences of #{cancelling_flavor} the trial for #{this_business.name}."
      redirect_back fallback_location: settings_billing_enterprise_path(this_business)
    else
      cancelled_flavor = this_business.trial_expired? ? "deleted" : "cancelled"
      flash[:notice] = "Your GitHub Enterprise trial, #{this_business.name}, has been #{cancelled_flavor}."
      this_business.cancel_trial(current_user)
      redirect_to "/"
    end
  end

  sig { void }
  def cancel_addon_trial # rubocop:todo GitHub/UseRestfulActions
    removed_successfully = false

    case params[:addon_id]
    when "advanced-security-licenses"
      result = this_business.end_advanced_security_trial_without_purchasing_now(
        actor: current_user,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month,
        is_stafftools_action: false,
      )
      removed_successfully = result.ok?
    when "copilot-business-seats"
      copilot_business = Copilot::Business.new(this_business)
      copilot_business.cancel_copilot_business_trials(current_user)
      removed_successfully = copilot_business.ongoing_organization_trials.empty?
    end

    if removed_successfully
      flash[:notice] = "#{params[:addon_label]} has been removed from #{this_business.name}."
      redirect_back fallback_location: settings_billing_enterprise_path(this_business)
    else
      add_on_name = params[:addon_label] || "the add-on"
      flash[:error] = "Removing #{add_on_name} from #{this_business.name} was not successful."
      redirect_back fallback_location: settings_billing_enterprise_path(this_business)
    end
  end

  sig { void }
  def update_payment_method # rubocop:todo GitHub/UseRestfulActions
    if no_payment_details?
      flash[:error] = "Please enter your payment information."
    elsif this_business.has_valid_payment_method? && !this_business.customer.has_valid_address_for_tax?
      flash[:error] = "Please edit or resubmit your billing information before updating your payment method."
    else
      if this_business.remove_azure_subscription_on_adding_cc_paypal?
        this_business.clear_azure_subscription_references!
      end

      has_payment_method = this_business.has_credit_card? || this_business.has_paypal_account?
      updated_or_added = has_payment_method ? "updated" : "added"
      details = payment_details.merge(actor: current_user)
      result = set_payment_method(details)

      if result.success?
        unless has_payment_method
          this_business.enable_automatic_self_serve_payment(current_user, update_zuora_account: false)
        end

        if this_business.has_failed_trial_authorization?
          Billing::AuthAndCapture::AuthorizeTrialJob.perform_later(this_business, current_user)
        end

        if payment_details_includes_paypal?
          flash[:notice] = "Your PayPal account has been successfully #{updated_or_added}."
        else
          flash[:notice] = "Your credit card has been successfully #{updated_or_added}."
        end
      else
        error_message = result.error_message
        GitHub.context.push(error: error_message.to_s)
        Audit.context.push(error: error_message.to_s)

        if error_message.respond_to?(:metadata)
          GitHub.context.push(metadata: error_message.metadata)
          Audit.context.push(metadata: error_message.metadata)
        end

        flash[:error] = error_message.to_s
      end
    end
    if this_business.billed_via_billing_platform?
      if params[:return_to].present?
        safe_redirect_to params[:return_to],
        fallback: enterprise_billing_payment_information_path(this_business)
      else
        redirect_to enterprise_billing_payment_information_path(this_business)
      end
    else
      if params[:return_to].present?
        safe_redirect_to params[:return_to],
        fallback: settings_billing_tab_enterprise_path(this_business, tab: :payment_information)
      else
        redirect_to settings_billing_tab_enterprise_path(this_business, tab: :payment_information)
      end
    end
  end

  sig { void }
  def update_payment_information # rubocop:todo GitHub/UseRestfulActions
    if update_trade_screening_record(skip_redirect: true)
      if this_business.trial? || this_business.upgrading_from_organization? || this_business.being_created_from_coupon?
        this_business.create_billing_customer_and_plan_subscription
      end
    end

    if this_business.billed_via_billing_platform?
      if params[:return_to].present?
        safe_redirect_to params[:return_to],
        fallback: enterprise_billing_payment_information_path(this_business)
      else
        redirect_to enterprise_billing_payment_information_path(this_business)
      end
    else
      if params[:return_to].present?
        safe_redirect_to params[:return_to],
        fallback: settings_billing_tab_enterprise_path(this_business, tab: :payment_information)
      else
        redirect_to settings_billing_tab_enterprise_path(this_business, tab: :payment_information)
      end
    end
  end

  sig { void }
  def payment_history # rubocop:todo GitHub/UseRestfulActions
    if this_business.disable_legacy_billing_page?
      redirect_to enterprise_billing_payment_history_index_path(this_business)
    else
      payment_records =
      Billing::Settings::PaymentHistory::PaymentRecord.payment_records(target: this_business)
      payment_records = payment_records.paginate(
        page: current_page,
        per_page: PER_PAGE
      )
      render "businesses/billing_settings/payment_history", locals: { target: this_business, payment_records: payment_records }
    end
  end

  sig { void }
  def convert_trial # rubocop:todo GitHub/UseRestfulActions
    actor = current_user

    new_seats = params[:seats]&.to_i
    seat_limit = this_business.seat_limit_for_upgrades

    if new_seats && new_seats > seat_limit
      flash[:error] = "You can only add up to #{seat_limit} seats when upgrading."
      return redirect_to billing_upgrade_enterprise_path(this_business)
    end
    this_business.plan_duration = params[:plan_duration] unless params[:plan_duration].blank?
    this_business.seats = new_seats unless new_seats.blank?
    this_business.save

    if activating_metered_ghe?
      talk_to_sales = params[:talk_to_sales] == "on" ? :YES : :NO
      this_business.talk_to_sales = talk_to_sales
    end

    if this_business.upgrade_from_trial(actor)
      if activating_metered_ghe?
        Licensing::TransitionEnterpriseToMeteredLicensingJob.perform_later(this_business, trial_upgrade: true, actor: actor)

        flash[:notice] = "Successfully activated GitHub Enterprise."
      else
        flash[:notice] = "Your GitHub Enterprise purchase will complete when your payment is successful."
      end

      analytics_event(
        category: "enterprise_trial_account",
        action: "complete_github_enterprise_purchase",
        label: "enterprise_id:#{this_business.id};seats:#{this_business.seats};duration:#{this_business.plan_duration}"
      )
      redirect_to enterprise_path(this_business)
    else
      flash[:error] = "Failed to complete GitHub Enterprise purchase. Please try again later or contact support."
      redirect_to billing_upgrade_enterprise_path(this_business)
    end
  end

  sig { void }
  def update_metered_via_azure  # rubocop:todo GitHub/UseRestfulActions

    if params[:metered_via_azure] == "false" && !this_business.customer&.can_disable_metered_via_azure?
      GitHub.dogstats.increment("azure.businesses.disable_subscription_id_attempt")
      flash[:error] = "Azure subscription cannot be disabled until your next metered cycle on #{this_business.next_metered_billing_cycle_starts_at.to_date.to_formatted_s(:long)}."
      if this_business.billed_via_billing_platform?
        redirect_to enterprise_billing_payment_information_path(this_business)
      else
        redirect_to settings_billing_tab_enterprise_path(this_business, tab: :payment_information)
      end
      return
    end

    if params[:metered_via_azure] == "true" && this_business.customer&.metered_via_azure_key.present?
      Billing::Kv.store.set(this_business.customer.metered_via_azure_key, Time.now.to_s, expires: this_business.next_metered_billing_cycle_starts_at)
    end

    if this_business.customer&.update(metered_via_azure: params[:metered_via_azure])
      flash[:notice] = "Successfully updated metered billing settings."
    else
      flash[:error] = "Failed to update metered billing settings."
    end

    if this_business.billed_via_billing_platform?
      redirect_to enterprise_billing_payment_information_path(this_business)
    else
      redirect_to settings_billing_tab_enterprise_path(this_business, tab: :payment_information)
    end
  end

  private

  sig { returns(T::Boolean) }
  def spending_limit_allowed?
    Billing::Budget.configurable?(this_business) || billing_privileges_allowed?
  end

  sig { returns(T::Boolean) }
  def billing_privileges_allowed?
    this_business.owner?(current_user) && this_business.can_self_serve? && !this_business.invoiced?
  end

  sig { returns(ActionController::Parameters) }
  memoize def members_can_make_purchases_params
    params.require(:business).permit(:members_can_make_purchases)
  end

  sig { void }
  def business_trial_required
    render_404 unless this_business.trial?
  end

  sig { void }
  def trial_conversion_not_initiated_required
    render_404 if this_business.trial_conversion_initiated?
  end

  sig { params(payment_details: T::Hash[Symbol, T.untyped]).returns(GitHub::Billing::Result) }
  def set_payment_method(payment_details)
    timeout(28) do
      if this_business.customer_zuora_account_id.present?
        GitHub::Billing.update_payment_method(
          this_business,
          payment_details.merge(
            auto_pay: this_business.customer.auto_pay_reasons.empty?
          )
        )
      else
        GitHub::Billing.create_customer(this_business, payment_details, actor: current_user)
      end
    end
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def business_fields
    params.require(:business).permit(:seats)
  end

  sig { returns(Integer) }
  def trial_seat_count
    Billing::EnterpriseCloudTrial::INITIAL_SEAT_COUNT
  end

  # This method is being used to redirect based on whether or not the
  # user is in Billing Vnext. Once Billing Vnext is the only billing path,
  # this can be removed in favor of just using the Vnext path.
  sig { params(dialog: T::Boolean, settings: T.untyped).returns(String) }
  def redirect_path(dialog: false, **settings)
    if params[:redirect_path].present?
      params[:redirect_path] += @code.nil? ? "" : "?dialog=true"
    else
      if this_business.billed_via_billing_platform?
        enterprise_billing_payment_information_path(
          this_business,
          **settings
        )
      else
        settings_billing_tab_enterprise_path(
          this_business,
          **settings
        )
      end
    end
  end

  sig { override.returns T.any(Business, Symbol) }
  def target_for_conditional_access
    # This is needed because TradeControlsControllerMethods includes OrganizationsHelper
    # which also defines target_for_conditional_access for organizations so there is a conflict.
    Businesses::BusinessController.instance_method(:target_for_conditional_access).bind(self).call
  end

  sig { returns(T::Boolean) }
  def activating_metered_ghe?
    this_business.metered_plan? && this_business.has_valid_payment_method?
  end
end
