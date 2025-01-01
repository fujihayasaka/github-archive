# typed: strict
# frozen_string_literal: true

class Stafftools::ReceiptsController < StafftoolsController
  extend T::Sig

  before_action :ensure_billing_enabled
  before_action :ensure_transaction_exists, only: [:create]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    only: [:show]

  sig { void }
  def create
    transaction = T.must(self.transaction)
    if transaction.success?
      email = if transaction.is_refund?
        transaction.create_refund_email(
          refund_transaction: transaction,
          refund_amount_in_cents: transaction.amount_in_cents.to_i
        )
      else
        BillingNotificationsMailer.receipt(billable_entity, transaction)
      end

      if email.deliver_later
        flash[:notice] = "Receipt sent to #{billable_entity&.billing_email}"
      else
        flash[:error] = "Failed to send receipt to #{billable_entity&.billing_email}"
      end
    else
      flash[:error] = "Receipt not sent for failed transaction."
    end

    redirect_to return_path
  end

  sig { void }
  def show
    receipt = ::Billing::Receipt.new(T.must(transaction), viewer: current_user)
    @receipt ||= T.let(receipt, T.nilable(::Billing::Receipt))

    respond_to do |format|
      format.text do
        render "mailers/billing_notifications/receipt"
      end
      format.pdf do
        send_data(@receipt.to_pdf(show_email_address: false),
          filename: @receipt.pdf_filename,
          type: "application/pdf",
          disposition: "inline",
        )
      end
      format.html do
        send_data(@receipt.to_pdf(show_email_address: false),
          filename: @receipt.pdf_filename,
          type: "application/pdf",
          disposition: "attachment",
        )
      end
    end
  end

  private

  sig { returns(T.nilable(T.any(::Billing::Types::Account, ::Billing::DeadUser))) }
  memoize def billable_entity
    transaction&.billable_entity
  end

  sig { returns(T.nilable(Billing::BillingTransaction)) }
  memoize def transaction
    id = params[:id]
    ::Billing::BillingTransaction.find_by(transaction_id: id)
  end

  sig { void }
  def ensure_transaction_exists
    render_404 unless transaction
  end

  sig { returns(T.any(String, Symbol)) }
  def return_path
    if this_user.present?
      :back
    else
      stafftools_billing_transaction_path(transaction_id: params[:id])
    end
  end
end
