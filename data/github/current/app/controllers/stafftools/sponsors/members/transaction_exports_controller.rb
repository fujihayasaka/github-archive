# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::TransactionExportsController < Stafftools::SponsorsController
  layout "application"

  before_action :require_fiscal_host

  def create
    timeframe = params[:timeframe].presence || :all
    ExportSponsorsTransactionsJob.perform_later(this_sponsorable, timeframe: timeframe, actor: current_user,
      recipient: current_user)
    flash[:notice] = "You've started an export of #{this_sponsorable}'s transactions. " \
      "You'll receive an email at #{current_user.email} shortly with the export attached."
    redirect_to stafftools_sponsors_member_path(this_sponsorable)
  end

  private

  def require_fiscal_host
    unless this_listing.fiscal_host?
      flash[:error] = "You can only export transactions for fiscal hosts."
      redirect_to stafftools_sponsors_member_path(this_sponsorable)
    end
  end
end
