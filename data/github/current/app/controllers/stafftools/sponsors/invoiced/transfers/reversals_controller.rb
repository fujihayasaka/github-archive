# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Invoiced::Transfers::ReversalsController < StafftoolsController
  before_action :sponsors_required

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
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:new],
    optional: true

  def new
    render "stafftools/sponsors/invoiced/transfers/reversals/new", locals: {
      sponsor: sponsor,
      transfer: transfer,
      reversal: transfer.reversals.build,
    }
  end

  def create
    reversal = transfer.reversals.build(reversal_params)

    if reversal.save
      InvoicedSponsorshipTransferReversalJob.perform_later(reversal)
      flash[:notice] = "Successfully enqueued new transfer reversal"
      redirect_to stafftools_sponsors_invoiced_sponsor_transfers_path(sponsor)
    else
      flash.now[:error] = "Couldn‘t create new transfer reversal: #{reversal.errors.full_messages.to_sentence}"

      render "stafftools/sponsors/invoiced/transfers/reversals/new", locals: {
        sponsor: sponsor,
        transfer: transfer,
        reversal: reversal,
      }
    end
  end

  private

  memoize def sponsor
    User.find_by!(login: params[:invoiced_sponsor_id])
  end

  memoize def transfer
    sponsor.invoiced_sponsorship_transfers_as_sponsor.completed.find(params[:transfer_id])
  end

  def reversal_params
    params.require(:invoiced_sponsorship_transfer_reversal).permit(
      :amount_in_dollars,
    ).merge(actor: current_user)
  end
end
