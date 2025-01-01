# typed: strict
# frozen_string_literal: true

class PaymentMethodController < ApplicationController
  extend T::Sig

  include BillingSettingsHelper
  include OrganizationsHelper
  include ColorHelper

  before_action :ensure_billing_enabled
  before_action :login_required
  before_action :ensure_target
  before_action :ensure_target_is_billable
  before_action :ensure_target_billing_is_not_enterprise_managed
  before_action :add_csp_exceptions, only: :show
  before_action only: [:show, :zuora_payment_show] do
    T.bind(self, PaymentMethodController)
    check_trade_compliance(target: target)
  end

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Copilot,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:show_modal]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:zuora_payment_page_signature]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:zuora_payment_show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:zuora_payment_show, :zuora_payment_page_signature, :show_modal],
    optional: true


  CSP_EXCEPTIONS = T.let({
    img_src: [GitHub.paypal_checkout_url].freeze,
    connect_src: [GitHub.braintreegateway_url, GitHub.braintree_analytics_url].freeze,
  }.freeze, T::Hash[Symbol, T::Array[String]])

  sig { void }
  def zuora_payment_show # rubocop:todo GitHub/UseRestfulActions
    return render_404 if !T.must(request).xhr?

    # Ensure payment method ID is alphanumeric 32 characters
    if params[:payment_method_id].nil? || params[:payment_method_id] !~ /\A[0-9a-zA-Z]{32}\z/
      return render_404
    end

    begin
      payment_method = GitHub.zuorest_client.get_payment_method(params[:payment_method_id])
    rescue Zuorest::HttpError => e
      Failbot.report!(e, app: "github-zuora")
      return render_404
    end

    return render_404 if payment_method["Type"] != "CreditCard"
    return render_404 if payment_method["CreditCardHolderName"] != T.must(current_user).id.to_s

    render json: {
      expiration_month: payment_method["CreditCardExpirationMonth"],
      expiration_year: payment_method["CreditCardExpirationYear"],
      masked_number: payment_method["CreditCardMaskNumber"],
      card_type: payment_method["CreditCardType"],
    }
  end

  sig { void }
  def show
    target = T.cast(self.target, User)
    @plan = GitHub::Plan.find(params[:plan]) if params[:plan]

    if @plan && !Billing::ChangeSubscription.can_perform?(target, plan: @plan, actor: T.must(current_user))
      flash[:error] = "#{@plan.display_name.capitalize} plan isn't available for #{target}"
    end

    if target.no_verified_emails?
      flash[:error] = "At least one email address must be verified to add or update your payment method"
      return redirect_to target_billing_path(target)
    end

    if target.spammy?
      flash[:error] = ::Billing::Zuora::HostedPaymentsPage::SPAMMY_MESSAGE
      return redirect_to target_billing_path(target)
    end

    instrument_loaded_page

    render "payment_method/show", locals: { target: target }
  end

  sig { void }
  def show_modal # rubocop:todo GitHub/UseRestfulActions
    include_modal_chrome = params[:omit_modal_chrome] != "1"
    render partial: "payment_method/show_modal", locals: {
      target: target,
      include_modal_chrome: include_modal_chrome,
    }
  end

  sig { void }
  def destroy
    payment_method = target.friendly_payment_method_name # find out what it is before we clear it.
    current_user = T.must(self.current_user)
    target = self.target

    if target.payment_method && target.payment_method.clear_payment_details(current_user)

      if target.is_a?(Organization)
        # this will remove any linked trade screening record from the org if the current user
        # is not the owner of the trade screening record.
        unless current_user.has_trade_screening_record_linked_to_org?(organization: target)
          current_user.unlink_trade_screening_record_from_org(organization: target)
        end
      end
      flash[:notice] = "Your #{payment_method} has been removed."
    else
      flash[:error] = "Failed to remove your #{payment_method}. #{GitHub.support_link_text} for help."
    end

    safe_redirect_to params[:return_to], fallback: target_billing_path(target)
  end

  sig { void }
  def zuora_payment_page_signature # rubocop:todo GitHub/UseRestfulActions
    manual_payment = params[:manual_payment].to_s.include?("true")
    invoices = params[:invoices]
    payment_gateway = params[:payment_gateway]

    preferred_color_mode = ColorMode.from_name(cookies[:preferred_color_mode])
    color_theme = active_color_mode(preferred_color_mode: preferred_color_mode)

    page_name = zuora_settings_compact_payment_page?(manual_payment) ? :settings_compact : :settings_regular

    payments_page = ::Billing::Zuora::HostedPaymentsPage.new(
      page_name:  page_name,
      target: target,
      manual_payment: manual_payment,
      color_theme: color_theme,
      host: T.must(request).host,
      invoices: invoices,
      payment_gateway: payment_gateway
    )

    render json: payments_page.params
  end

  private

  sig { returns(T.any(Symbol, ::Billing::Types::Account)) }
  def target_for_conditional_access
    return :no_target_for_conditional_access unless target! # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    target
  end

  sig { returns(T::Boolean) }
  def data_collection_view_context_present?
    return false unless target.present?

    signature_view_context = params[:view_context]
    signature_view_context = if signature_view_context
      Billing::Zuora::HostedPaymentsPage::SIGNATURE_VIEW_CONTEXTS.include?(signature_view_context) ? signature_view_context : nil
    end
    !!(signature_view_context.present? && (target.has_saved_trade_screening_record? || target.live_sdn_screening_enabled?))
  end

  sig { void }
  def ensure_target
    render_404 if target!.nil?
  end

  sig { returns(Billing::Types::Account) }
  memoize def target
    T.must(target!)
  end

  sig { returns(T.nilable(::Billing::Types::Account)) }
  def target!
    if params[:organization_id]
      org = current_organization_for_member_or_billing
      if org && org.billing_manageable_by?(current_user)
        org
      end
    elsif params[:business_id]
      business = Business.find_by(slug: params[:business_id])
      business if business&.owner?(current_user) || business&.billing_manager?(current_user)
    else
      current_user
    end
  end

  sig { void }
  def ensure_target_is_billable
    render_404 unless target.billable?
  end

  sig { void }
  def ensure_target_billing_is_not_enterprise_managed
    target = self.target
    render_404 if target.is_a?(Organization) && target.business
  end

  sig { void }
  def instrument_loaded_page
    return if !target.user? || target.has_saved_trade_screening_record?

    GlobalInstrumenter.instrument("account_screening_profile.form_loaded", {
      actor: current_user,
      action: :LOADED,
      payment_flow_page: "BILLING",
      target_type: target.instrumentation_object_type,
      target_id: target.id,
      target_name: target.display_login,
    })
  end

  sig { params(manual_payment: T::Boolean).returns(T::Boolean)  }
  def zuora_settings_compact_payment_page?(manual_payment)
    return true if manual_payment && !target.organization?
    return true if data_collection_view_context_present?
    return true if target.is_a?(Business)
    false
  end
end
