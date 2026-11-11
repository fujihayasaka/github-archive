# typed: strict
# frozen_string_literal: true

class Businesses::Billing::PaymentHistoryController < Businesses::BillingsController
  before_action :business_access_required

  PER_PAGE = 10

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
    if this_business.billed_via_billing_platform?
      payment_records =
      Billing::Settings::PaymentHistory::PaymentRecord.payment_records(target: this_business)
      payment_records = payment_records.paginate(
        page: current_page,
        per_page: PER_PAGE
      )
      render "businesses/billing_settings/payment_history", locals: { business: this_business, payment_records: payment_records }
    else
      render_404
    end
  end
end
