# typed: true
# frozen_string_literal: true

class InvoicesController < ApplicationController
  include BillingSettingsHelper

  before_action :ensure_billing_enabled
  before_action :login_required
  before_action :ensure_target
  before_action :ensure_invoices_enabled_for_users
  before_action :ensure_target_billing_manageable
  before_action :require_invoice, only: [:show, :pay, :payment_method]

  before_action :add_csp_exceptions, only: :show
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:pay]

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
    only: [:payment_method]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:payment_page_signature]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:pay, :show], optional: true

  stylesheet_bundle :settings

  CSP_EXCEPTIONS = {
    object_src: [GitHub.host_name].freeze,
    plugin_types: ["application/pdf"].freeze,
  }

  def show
    instrument_show

    headers["Content-Disposition"] = "inline; filename=\"#{invoice.number&.downcase}.pdf\""
    render body: Base64.decode64(invoice.body), content_type: "application/pdf"
  end

  def pay # rubocop:todo GitHub/UseRestfulActions
    raise Billing::Zuora::Error, "unsuccessful arguments for invoice payment" unless params[:success] == "true"
    payload = { AccountId: target.customer.zuora_account_id,
                Amount: invoice.balance,
                AppliedCreditBalanceAmount: 0,
                AppliedInvoiceAmount: invoice.balance,
                EffectiveDate: Date.today.to_s,
                InvoiceId: invoice.id,
                PaymentMethodId: params[:ref_id],
                Status: "Processed",
                Type: "Electronic" }
    GitHub.zuorest_client.create_payment(payload)

    instrument_pay(payment_method_id: params[:ref_id])

    if target.is_a?(Business) && target.billed_via_billing_platform?
      flash[:success] = "Payment successful. Your invoice has been paid."
      redirect_to enterprise_billing_past_invoices_path(target)
    else
      redirect_to target_billing_path(target)
    end
  rescue Zuorest::HttpError, Billing::Zuora::Error, Faraday::TimeoutError => e
    payment_processor_error(error: e)
  ensure
    ZuoraDeleteCardsFromAccountJob.perform_later(target.customer.zuora_account_id)
  end

  def payment_method # rubocop:todo GitHub/UseRestfulActions
    if invoice.paid?
      payment_processor_error(message: "This invoice is already fully paid.")
    else
      SecureHeaders.append_content_security_policy_directives(
        request,
        frame_src: [GitHub.zuora_payment_page_server],
      )
      render "billing_settings/invoice_payment_method", locals: { target: target, invoice: invoice }
    end
  end

  def payment_page_signature # rubocop:todo GitHub/UseRestfulActions
    payments_page = ::Billing::Zuora::HostedPaymentsPage.new(
      page_name:  :invoices,
      target: current_user,
      account_id: target.customer.zuora_account_id,
      host: request.host,
    )

    render json: payments_page.params
  rescue Zuorest::HttpError => e
    payment_processor_error(error: e)
  end

  private

  def target_for_conditional_access
    target
  end

  def ensure_target
    render_404 if target.nil?
  end

  def ensure_invoices_enabled_for_users
    render_404 if target.user? && target == current_user && !GitHub.flipper[:receipts_use_zuora_pdf].enabled?(current_user)
  end

  def ensure_target_billing_manageable
    if target.is_a?(Business) || target.is_a?(Organization)
      render_404 unless target.adminable_by?(current_user) || target.billing_manager?(current_user)
    end
  end

  memoize def target
    if params[:slug].present?
      business
    elsif  params[:organization_id]
      organization
    else
      current_user
    end
  end

  memoize def business
    Business.find_by(slug: params[:slug])
  end

  memoize def organization
    Organization.find_by(login: params[:organization_id])
  end

  memoize def invoice
    ::Billing::Zuora::Invoice.new(params[:invoice_number])
  end

  def require_invoice
    render_404 unless invoice&.account_id == target&.customer&.zuora_account_id
  rescue Zuorest::HttpError => e
    Failbot.report!(e, app: "github-zuora")
    render_404
  end

  def payment_processor_error(error: nil,
                              message: "There was a problem communicating with our payment provider. Please try again.",
                              redirect_url: target_billing_path(target))
    Failbot.report(error, app: "github-zuora") if error
    flash[:error] = message
    redirect_to redirect_url
  end

  def instrument_show
    GitHub.instrument("invoice.download", invoice_payload)
  end

  def instrument_pay(payment_method_id:)
    payload = invoice_payload.merge(
      amount_applied_to_invoice: Billing::Money.new(invoice.balance * 100).format,
      payment_method_id: payment_method_id,
    )

    GitHub.instrument("invoice.pay", payload)
  end

  def invoice_payload
    payload = { invoice_number: invoice.number.upcase }

    if target.is_a?(Business)
      payload.update(business: business)
    else
      payload.update(org: organization)
    end

    if current_user.site_admin?
      payload.update(GitHub.guarded_audit_log_staff_actor_entry(current_user))
    else
      payload.update(actor: current_user)
    end

    payload
  end
end
