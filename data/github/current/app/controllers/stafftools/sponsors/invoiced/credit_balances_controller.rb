# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Invoiced::CreditBalancesController < StafftoolsController
  before_action :sponsors_required
  before_action :require_invoiced_sponsor

  def create
    amount = Billing::Money.parse(params[:amount])

    result = Billing::Sponsors::Invoiced::IncreaseCreditBalance.perform(
      actor: current_user,
      sponsor: sponsor,
      amount: amount,
      comment: params[:comment],
      reference_id: params[:reference_id]
    )

    if result.success?
      flash[:notice] = "Added #{amount.format} USD to #{sponsor}'s sponsorship credit balance"
    else
      flash[:error] = "Failed to add credit balance; #{result}"
    end

    redirect_to billing_stafftools_user_path(sponsor)
  end

  private

  memoize def sponsor
    User.find_by_login(params[:invoiced_sponsor_id])
  end

  def require_invoiced_sponsor
    render_404 unless sponsor&.sponsors_invoiced?
  end
end
