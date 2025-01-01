# typed: true
# frozen_string_literal: true

class Sponsors::FiscalHost::TransactionExportsController < ApplicationController
  include Sponsors::AdminableControllerValidations

  before_action :non_waitlisted_sponsors_listing_required
  before_action :require_acceptance_into_sponsors_program
  before_action :fiscal_host_sponsors_listing_required

  def create
    timeframe = params[:timeframe].presence || :all
    ExportSponsorsTransactionsJob.perform_later(sponsorable, timeframe: timeframe,
      actor: current_user)
    flash[:notice] = "You've started an export of your transactions! " \
      "You'll receive an email at #{sponsors_listing.contact_email_address} shortly with the export " \
      "attached."
    redirect_to sponsorable_dashboard_fiscal_host_path(sponsorable)
  end

  private

  def target_for_conditional_access
    return :no_target_for_conditional_access unless sponsorable # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    sponsorable
  end

  def sponsors_listing
    T.must_because(sponsorable_sponsors_listing) do
      "non-nil sponsors listing required in #before_action fiscal_host_sponsors_listing_required"
    end
  end
end
