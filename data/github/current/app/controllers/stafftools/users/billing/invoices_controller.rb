# typed: true
# frozen_string_literal: true

class Stafftools::Users::Billing::InvoicesController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods

  layout :billing_layout

  before_action :ensure_user_exists

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    render "stafftools/billing/invoices/index", locals: {
      billable_entity: this_user,
      invoices: invoices,
      can_make_payment: false,
    }
  end

  def show
    instrument_show
    headers["Content-Disposition"] = "inline; filename=\"#{invoice.number&.downcase}.pdf\""
    render body: Base64.decode64(invoice.body), content_type: "application/pdf"

  end

  private

  memoize def invoice
    ::Billing::Zuora::Invoice.new(params[:invoice_number])
  end

  def instrument_show
    GitHub.instrument("invoice.download", invoice_payload)
  end

  def invoice_payload
    payload = { invoice_number: invoice.number.upcase }

    #if target.is_a?(Business)
    #  payload.update(business: business)
    #else
    #  payload.update(org: organization)
    #end

    if current_user.site_admin?
      payload.update(GitHub.guarded_audit_log_staff_actor_entry(current_user))
    else
      payload.update(actor: current_user)
    end

    payload
  end

  def invoices
    this_user.invoices
  rescue Zuorest::HttpError, Faraday::Error => e
    flash.now[:error] = "There was an error retrieving your invoices. Please try again later."
    Failbot.report!(e, app: "github-zuora")
    []
  end
end
