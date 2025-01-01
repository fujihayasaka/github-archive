# typed: true
# frozen_string_literal: true

class Stafftools::DeletedAccountTransactionsController < StafftoolsController

  before_action :ensure_billing_enabled
  before_action :ensure_deleted_account

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests, # needed for queries
    only: %i(index)

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    render "stafftools/deleted_account_transactions/index", locals: {
      billable_entity: billable_entity,
      charges: charges
    }
  end

  private

  def ensure_deleted_account
    if active_user
      redirect_to stafftools_user_billing_history_path(active_user)
    elsif active_business
      redirect_to stafftools_enterprise_billing_payment_history_path(active_business)
    end
  end

  memoize def active_user
    User.find_by(id: params[:deleted_user_id], login: params[:deleted_handle])
  end

  memoize def active_business
    Business.find_by(id: params[:deleted_enterprise_id])
  end

  memoize def deleted_business
    Business.including_deleted.find_by(id: params[:deleted_enterprise_id])
  end

  memoize def transactions
    if params[:deleted_user_id]
      ::Billing::BillingTransaction
        .includes(:live_user, :notes, :refund)
        .preload(line_items: :sponsors_tier)
        .non_refunds
        .where(user_id: params[:deleted_user_id])
        .descending
    elsif params[:deleted_enterprise_id] && deleted_business
      ::Billing::BillingTransaction
        .where(customer_id: deleted_business.customer_id)
        .includes(:refund)
        .preload(line_items: :sponsors_tier)
        .non_refunds
        .descending
    else
      [::Billing::BillingTransaction.find_by(transaction_id: params[:transaction_id])]
    end
  end

  memoize def charges
    Stafftools::Billing::PaymentRecord.for_billing_transactions(transactions.to_a.compact)
  end

  memoize def billable_entity
    if params[:deleted_enterprise_id]
      deleted_business
    else
      User.new(login: params[:deleted_handle])
    end
  end
end
