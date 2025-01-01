# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Invoiced::PaymentRunsController < StafftoolsController
  before_action :sponsors_required
  before_action :require_sponsor, only: :create

  def create
    unless sponsor&.sponsors_invoiced?
      flash[:notice] = "#{sponsor} does not have a sponsorship-specific Zuora account."
      return redirect_to(billing_stafftools_user_path(sponsor))
    end

    SponsorsBillingCreditBalanceInvoiceCollectionJob.perform_later(sponsor)

    sponsor.instrument_sponsors_payment_run(actor: current_user)

    flash[:notice] = "Started Sponsors-specific payment run for #{sponsor}"

    redirect_to billing_stafftools_user_path(sponsor)
  end

  private

  memoize def sponsor
    User.find_by(login: params[:invoiced_sponsor_id])
  end

  def require_sponsor
    render_404 unless sponsor
  end
end
