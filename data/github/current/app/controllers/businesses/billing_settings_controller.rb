# typed: strict
# frozen_string_literal: true

class Businesses::BillingSettingsController < Businesses::BusinessController
  include BillingSettingsHelper
  include Contacts::SharedControllerMethods
  include Billing::AzureOauthStateManagement
  T.unsafe(self).react_bundle_name = "billing-app"

  before_action :ensure_billing_enabled
  before_action :business_owner_required, only: :cancel_trial
  before_action :business_access_required, except: [:authenticate_azure]
  # Org admins need to be able to authenticate when modifying cost centers.
  before_action -> do
    T.bind(self, Businesses::BillingSettingsController)

    business_access_required(allow_org_owners: true)
  end, only: [:authenticate_azure]
  before_action :business_trial_required, only: [:cancel_trial, :convert_trial]
  before_action :business_trial_or_active_ghas_trial_required, only: [:cancel_addon_trial]
  before_action :eligible_for_self_serve_payment_required, only: [
    :payment_history,
    :update_payment_information,
    :update_payment_method,
  ]

  before_action :trial_conversion_not_initiated_required, only: [:convert_trial]
  before_action only: [:update_payment_method, :convert_trial] do
    T.bind(self, Businesses::BillingSettingsController)
    check_trade_compliance(target: this_business, redirect_url: enterprise_billing_payment_information_url(this_business), sdn_redirect: true)
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

  PER_PAGE = 10

  javascript_bundle "billing-settings"

  stylesheet_bundle :settings

  sig { void }
  def authenticate_azure # rubocop:todo GitHub/UseRestfulActions
    if params[:azure_state].blank?
      flash[:error] = "Missing state from Azure"
      return safe_redirect_to redirect_path
    end

    @azure_state = T.let(state_to_hash(state: params[:azure_state]), T.nilable(T::Hash[Symbol, T.untyped]))
    return safe_redirect_to redirect_path if @azure_state.nil?

    @code = T.let(@azure_state[:oauth_code], T.nilable(String))
    @redirect_path = T.let(@azure_state[:redirect_path], T.nilable(String))

    # This is true if we already sent the user to explicitly select a tenant
    explicit_tenant_selected = @azure_state[:explicit_tenant_selected] == true

    return safe_redirect_to redirect_path if @code.nil?

    client = Billing::Azure::BusinessSubscriptionClient.new(current_user, this_business)
    client.fetch_and_store_token(@code)

    tenants = client.fetch_tenants
    if !explicit_tenant_selected && !tenants.nil? && tenants.count > 1
      GitHub.dogstats.increment("azure.self_serve.showing_tenant_selection")

      path_settings = { show_subscriptions: true, anchor: "open_tenant_dialog" }

      # Ask user to select a tenant first
      return safe_redirect_to redirect_path(**path_settings)
    end

    GitHub.dogstats.increment("azure.self_serve.showing_subscription_selection")

    path_settings = { show_subscriptions: true, anchor: "open_dialog" }

    safe_redirect_to redirect_path(**path_settings)
  rescue JSON::JSONError
    flash[:error] = "Failed decoding state from Azure"
    safe_redirect_to redirect_path
  rescue Billing::AzureOauthStateManagement::AzureStateValidationError => e
    flash[:error] = "Authentication request invalid or expired. Please try again."
    safe_redirect_to redirect_path
  rescue Faraday::Error => e
    Failbot.report(e)
    flash[:error] = "Failed to fetch authentication information from Azure. Please try again."
    redirect_to enterprise_billing_payment_information_path(this_business)
  end

  sig { void }
  def show
    if params[:tab] == "billing_emails"
      return redirect_to enterprise_billing_contacts_path(this_business)
    end

    if params[:tab] == "payment_information" && !params[:show_subscriptions]
      return redirect_to enterprise_billing_payment_information_path(this_business)
    end

    if params[:tab] == "marketplace_apps"
      return redirect_to enterprise_billing_marketplace_apps_path(this_business)
    end

    if params[:tab] == "sponsorships"
      return redirect_to enterprise_billing_sponsorships_path(this_business)
    end

    if params[:tab] == "payment_history"
      return redirect_to enterprise_billing_payment_history_index_path(this_business)
    end

    if params[:tab] == "past_invoices"
      return redirect_to enterprise_billing_past_invoices_path(this_business)
    end

    redirect_to enterprise_billing_path(this_business)
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
      result = this_business.end_advanced_security_trial(
        actor: current_user,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month,
        is_stafftools_action: false,
      )
      removed_successfully = result.ok?
    when "copilot-business-seats"
      copilot_business = Copilot::Business.new(this_business)
      copilot_business.cancel_copilot_business_access(current_user)
      removed_successfully = Copilot::Business.new(this_business.reload).copilot_disabled?
    when "secret-protection-unbundled"
      begin
        BulkDisableService.disable_service_on_private_repos(
          this_business,
          current_user,
          :token_scanning,
          enablement_action: "trial_reset"
        )
        # Check if Secret Protection was successfully disabled by verifying 0 seats in use
        removed_successfully = this_business.secret_protection.seats_used == 0
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        Rails.logger.error("Failed to disable Secret Protection: #{e.message}")
        Failbot.report(e, {
          "code.namespace": self.class.name,
          "code.function": __method__,
        })
        removed_successfully = false
      end
    when "code-security-unbundled"
      begin
        BulkDisableService.disable_service_on_private_repos(
          this_business,
          current_user,
          :code_security,
          enablement_action: "trial_reset"
        )
        # Check if Code Security was successfully disabled by verifying 0 seats in use
        removed_successfully = this_business.code_security.seats_used == 0
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        Rails.logger.error("Failed to disable Code Security: #{e.message}")
        Failbot.report(e, {
          "code.namespace": self.class.name,
          "code.function": __method__,
        })
        removed_successfully = false
      end
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
      flash[:error] = tax_validation_error_message(this_business.customer)
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
    if params[:return_to].present?
      safe_redirect_to params[:return_to],
      fallback: enterprise_billing_payment_information_path(this_business)
    else
      redirect_to enterprise_billing_payment_information_path(this_business)
    end
  end

  sig { void }
  def remove_payment_method # rubocop:todo GitHub/UseRestfulActions
    payment_method = this_business.friendly_payment_method_name # find out what it is before we clear it.
    target = this_business

    log_target_information(target, T.must(self.class.name), __method__.to_s)

    if target.payment_method && target.payment_method.clear_payment_details(current_user)
      flash[:notice] = "Your #{payment_method} has been removed."
    else
      flash[:error] = "Failed to remove your #{payment_method}."
    end

    if params[:return_to].present?
      safe_redirect_to params[:return_to],
      fallback: enterprise_billing_payment_information_path(this_business)
    else
      redirect_to enterprise_billing_payment_information_path(this_business)
    end
  end

  sig { void }
  def update_payment_information # rubocop:todo GitHub/UseRestfulActions
    if update_billing_contact(skip_redirect: true)
      if this_business.trial? || this_business.upgrading_from_organization? || this_business.being_created_from_coupon?
        this_business.create_billing_customer_and_plan_subscription
      end
    end

    if params[:return_to].present?
      safe_redirect_to params[:return_to],
      fallback: enterprise_billing_payment_information_path(this_business)
    else
      redirect_to enterprise_billing_payment_information_path(this_business)
    end
  end

  sig { void }
  def payment_history # rubocop:todo GitHub/UseRestfulActions
    redirect_to enterprise_billing_payment_history_index_path(this_business)
  end

  sig { void }
  def convert_trial # rubocop:todo GitHub/UseRestfulActions
    if this_business.customer&.billing_locked?
      flash[:error] = "Your account is currently locked from purchases. Please update your payment information."
      return redirect_to billing_upgrade_enterprise_path(this_business)
    end

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

        this_business.set_customer_to_split_metered_offering(actor: actor)
        this_business.set_advanced_security_seats_for_entity(seats: 0, actor: actor, is_stafftools_action: true)

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

      redirect_to enterprise_billing_payment_information_path(this_business)
      return
    end

    if this_business.customer&.update(metered_via_azure: params[:metered_via_azure])
      flash[:notice] = "Successfully updated metered billing settings."
    else
      flash[:error] = "Failed to update metered billing settings."
    end

    redirect_to enterprise_billing_payment_information_path(this_business)
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
  def business_trial_or_active_ghas_trial_required
    # Allow access if business is in an enterprise trial OR has active GHAS trials
    # This supports both DFD GHAS trials and standalone GHAS trials
    render_404 unless this_business.trial? || this_business.has_active_advanced_security_trial?
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
    if @redirect_path.present?
      @redirect_path += @code.nil? ? "" : "?dialog=true"
    else
      enterprise_billing_payment_information_path(
        this_business,
        **settings
      )
    end
  end

  sig { override.returns T.any(Business, Symbol) }
  def target_for_conditional_access
    # This is needed because OrganizationsHelper also defines target_for_conditional_access for organizations so there is a conflict.
    Businesses::BusinessController.instance_method(:target_for_conditional_access).bind(self).call
  end

  sig { returns(T::Boolean) }
  def activating_metered_ghe?
    this_business.metered_plan? && this_business.has_valid_payment_method?
  end
end
