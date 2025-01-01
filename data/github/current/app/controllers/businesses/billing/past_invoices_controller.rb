# typed: strict
# frozen_string_literal: true

class Businesses::Billing::PastInvoicesController < Businesses::BillingsController
  before_action :business_access_required

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
    only: [:index]

  sig { void }
  def index
    if this_business.billed_via_billing_platform? && this_business.show_past_invoices_tab?(current_user)
      render "businesses/billing_platform/past_invoices", locals: { business: this_business, invoices: invoices }
    else
      render_404
    end
  end

  private

  sig { returns(T::Array[::Billing::Zuora::Invoice]) }
  def invoices
    @_invoices ||= T.let(Billing::Zuora::Invoice.invoices_for_account(this_business.customer&.zuora_account_id.to_s)
      .sort_by(&:invoice_date)
      .reverse, T.nilable(T::Array[::Billing::Zuora::Invoice]))
  rescue Zuorest::HttpError, Faraday::Error => e
    Failbot.report!(e, app: "github-zuora")
    @_invoices = []
  end
end
