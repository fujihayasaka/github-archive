# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::Billing::PaymentHistoryController < Stafftools::Businesses::BillingController

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  sig { void }
  def index
    transactions = this_business.billing_transactions
      .includes(:refund)
      .preload(line_items: :sponsors_tier)
      .non_refunds
      .descending
      .to_a

    charges = Stafftools::Billing::PaymentRecord.for_billing_transactions(transactions)
    # TODO: enterprise accounts currently don't support disputes
    disputes = []

    render "stafftools/billing/payment_history/index", locals: {
      billable_entity: this_business,
      charges: charges,
      disputes: disputes,
    }
  end
end
