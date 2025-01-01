# typed: strict
# frozen_string_literal: true

class Stafftools::BillingTransactionsController < StafftoolsController
  before_action :ensure_billing_enabled

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
    ApplicationRecord::IssuesPullRequests,
    only: %i(index)

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  sig { void }
  def index
    billing_transaction = nil
    if params[:transaction_id].present?
      billing_transaction = ::Billing::BillingTransaction.find_by(transaction_id: params[:transaction_id])
    end
    if billing_transaction && billing_transaction.live_user.present?
      redirect_to stafftools_user_billing_history_path(
        billing_transaction.live_user,
        anchor: "transaction-#{billing_transaction.transaction_id}"
      )
    elsif billing_transaction && billing_transaction.billable_business?
      redirect_to stafftools_enterprise_billing_payment_history_path(
        billing_transaction.billable_entity,
        anchor: "transaction-#{billing_transaction.transaction_id}"
      )
    elsif billing_transaction
      deleted_user_id = billing_transaction.user.id
      if deleted_user_id
        redirect_to stafftools_deleted_account_transactions_path(
          deleted_user_id: deleted_user_id,
          deleted_handle: billing_transaction.user.login,
          anchor: "transaction-#{billing_transaction.transaction_id}"
        )
      else
        redirect_to stafftools_deleted_account_transactions_path(
          deleted_user_id: nil,
          deleted_handle: nil,
          transaction_id: billing_transaction.transaction_id,
        )
      end
    elsif billing_transaction.nil?
      render "stafftools/billing_transactions/search"
    end
  end

  sig { void }
  def cancel_authorization_billing_transaction # rubocop:todo GitHub/UseRestfulActions
    id = params[:id]
    Billing::CancelAuthorizationBillingTransactionJob.perform_now(billing_transaction_id: id)

    flash[:notice] = "Cancel authorization hold enqueued"

    redirect_to :back
  end
end
