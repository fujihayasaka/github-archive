# typed: strict
# frozen_string_literal: true

class BillingSettings::PaymentsController < ApplicationController
  include BillingSettingsHelper
  include OrganizationsHelper
  include Businesses::Concerns::BusinessLayoutClusterDependencies
  include Billing::ManualPaymentRedirect

  # cancel_pending is a DELETE; opt it into cluster-dependency validation (GET-only by default).
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "BillingSettings::PaymentsController#cancel_pending",
  ].freeze

  # CSS class (and selector) for the hidden form that billing/zuora.ts submits after a successful
  # manual (e.g. India RBI) payment to finalize a deferred product upgrade by re-issuing the
  # original request to the product's create endpoint.
  POST_SUCCESS_FORM_CLASS = "js-manual-payment-post-success-form"
  POST_SUCCESS_FORM_SELECTOR = ".#{POST_SUCCESS_FORM_CLASS}"

  before_action :ensure_billing_enabled
  before_action :login_required
  before_action :ensure_target
  before_action :ensure_target_is_billable
  before_action :disable_color_modes
  before_action do
    T.bind(self, BillingSettings::PaymentsController)

    check_trade_compliance(target: target)
  end
  before_action :ensure_positive_balance, only: [:new]

  javascript_bundle :billing, :"billing-settings"

  stylesheet_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:new], optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    only: [:cancel_pending]

  sig { void }
  def check # rubocop:todo GitHub/UseRestfulActions
    return head 404 if !request.xhr? || params[:payment_id].blank?

    if target.billing_transactions.exists?(platform_transaction_id: params[:payment_id])
      head 200
    else
      head 202
    end
  end

  sig { void }
  def new
    if !target.autopay_disabled_by_india_rbi?
      flash[:error] = "Manual payments are not allowed for this account"
      return redirect_to target_billing_url(target)
    end

    purpose = params[:purpose]&.to_sym
    invoice_id = params[:invoice_id]
    manual_payment = Billing::ManualPayment.new(
      target: target,
      # When scoping to a specific invoice, ignore any purpose param: the payment covers a single
      # invoice and purpose-based separation does not apply
      purpose: invoice_id.present? ? nil : purpose,
      invoice_id: invoice_id,
    )

    render "billing_settings/payments/separate", locals: {
      target: target,
      trade_screening_needed: target.user?,
      manual_payment: manual_payment,
      post_success_form: post_success_form,
      failure_redirect_to: failure_redirect_to,
    }
  end

  # Cancels a deferred upgrade the customer chose not to pay for: clears the pending advance-payment
  # invoice (so the outstanding-payment banner stops prompting) and drops the stashed finalization
  # details. Used by the Copilot outstanding-upgrade banner's "Cancel upgrade" action.
  sig { void }
  def cancel_pending # rubocop:todo GitHub/UseRestfulActions
    invoice_id = params[:invoice_id]
    if invoice_id.blank?
      flash[:error] = "No outstanding payment to cancel"
      return redirect_to target_billing_url(target)
    end

    customer = target.customer
    if customer
      Billing::AdvancePayment.cancel_pending_invoice!(customer: customer, invoice_id: invoice_id)
    end
    Billing::PendingManualPaymentUpgrade.delete(target: target, invoice_id: invoice_id)

    flash[:notice] = "Your upgrade has been cancelled."
    redirect_to target_billing_url(target)
  end

  private

  # The checkout page to send the customer back to when their manual payment can't be confirmed in
  # time, so they can retry activation once it finishes processing. Built from the return_to_path the
  # product stashed alongside the pending upgrade, flagged so the checkout page shows the retry banner.
  # Returns nil when the customer did not arrive via an upgrade that needs finalizing.
  sig { returns(T.nilable(String)) }
  def failure_redirect_to
    pending_upgrade = pending_upgrade_for_request
    return nil if pending_upgrade.nil?

    return_to_path = pending_upgrade.params["return_to_path"]
    return nil if return_to_path.blank?

    uri = URI.parse(return_to_path)
    query = Rack::Utils.parse_nested_query(uri.query)
    query[Billing::ManualPaymentRedirect::PAYMENT_PROCESSING_PARAM] = "true"
    uri.query = query.to_query
    uri.to_s
  end

  # Build the hidden "post-success" form that billing/zuora.ts submits after a successful manual
  # (e.g. India RBI) payment to finalize a deferred upgrade by re-issuing the original request to the
  # product's create endpoint (rather than waiting on the asynchronous payment webhook).
  #
  # The pending_upgrade (POST path + params) was supplied product-agnostically by whichever product
  # redirected the customer here, and stashed for this invoice (see Billing::ManualPaymentRedirect).
  # Returns a Hash for the view (with the :form_class and :form_selector used to locate the form), or
  # nil when the customer did not arrive via an upgrade that needs finalizing.
  sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def post_success_form
    pending_upgrade = pending_upgrade_for_request
    return nil if pending_upgrade.nil?

    {
      path: pending_upgrade.path,
      # Mark the re-POST so the product's create action can tell it's a manual-payment finalization
      # attempt (and send the customer back to retry activation rather than looping them back here if
      # the payment still isn't confirmed). See Billing::ManualPaymentRedirect.
      params: pending_upgrade.params.merge(Billing::ManualPaymentRedirect::FINALIZATION_PARAM => "true"),
      form_class: POST_SUCCESS_FORM_CLASS,
      form_selector: POST_SUCCESS_FORM_SELECTOR,
    }
  end

  # The pending upgrade (if any) the customer was redirected here to finalize. See post_success_form.
  sig { returns(T.nilable(::Billing::PendingManualPaymentUpgrade)) }
  memoize def pending_upgrade_for_request
    pending_manual_payment_upgrade(target: target, invoice_id: params[:invoice_id])
  end

  sig { void }
  def ensure_positive_balance
    # Skip when paying a specific invoice (e.g. an India RBI manual-payment redirect for a deferred
    # upgrade or a pay-as-you-go usage charge): the standalone invoice exists in Zuora but the account's
    # cached aggregate balance_in_cents may not be updated yet, so it can read as zero. The
    # invoice-scoped page handles the "nothing due" case on its own.
    return if params[:invoice_id].present?

    unless target.balance_in_cents.positive?
      flash[:error] = "No outstanding balance to pay"
      redirect_to :back
    end
  end

  sig { void }
  def ensure_target
    render_404 unless target!
  end

  sig { returns(User) }
  memoize def target
    T.must(target!)
  end

  sig { returns(T.nilable(User)) }
  def target!
    if params[:organization_id]
      org = current_organization_for_member_or_billing
      if org && org.billing_manageable_by?(current_user)
        org
      end
    else
      current_user
    end
  end

  sig { void }
  def ensure_target_is_billable
    render_404 unless target.billable?
  end
end
