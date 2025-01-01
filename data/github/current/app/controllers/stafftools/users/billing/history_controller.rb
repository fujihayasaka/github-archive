# typed: true
# frozen_string_literal: true

class Stafftools::Users::Billing::HistoryController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods

  layout :billing_layout

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
    return render_404 unless this_user.present?

    transactions = this_user.billing_transactions
      .includes(:live_user, :notes, :refund)
      .preload(line_items: [:sponsors_tier, :tax_items])
      .non_refunds
      .descending
      .to_a
    charges = Stafftools::Billing::PaymentRecord.for_billing_transactions(transactions)
    disputes = this_user.billing_dispute_records
    render "stafftools/billing/payment_history/index", locals: {
      billable_entity: this_user,
      charges: charges,
      disputes: disputes,
    }
  end
end
