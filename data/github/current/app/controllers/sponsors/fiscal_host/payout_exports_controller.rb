# typed: strict
# frozen_string_literal: true

class Sponsors::FiscalHost::PayoutExportsController < ApplicationController
  include Sponsors::AdminableControllerValidations

  before_action :non_waitlisted_sponsors_listing_required
  before_action :require_acceptance_into_sponsors_program
  before_action :fiscal_host_sponsors_listing_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  sig { void }
  def index
    sponsorable_login = T.must_because(sponsorable_login_param) { "#sponsorable_required ensures non-nil" }
    render Sponsors::Payouts::ExportFormComponent.new(
      stripe_payouts: stripe_payouts,
      form_url: sponsorable_dashboard_fiscal_host_payout_exports_path(sponsorable_login),
      success: stripe_payouts_success?,
      sponsorable_login: sponsorable_login,
    ), layout: false
  end

  sig { void }
  def create
    export = SponsorsListing::PayoutsExport.new(
      sponsors_listing: sponsorable_sponsors_listing,
      payout_id: payout_id,
      stripe_account: stripe_account,
    )

    if export.start_export_job(actor: current_user)
      flash[:notice] = "We've started exporting your payout information! " \
        "You'll receive an email at #{export.contact_email} shortly with the export attached."
    else
      flash[:error] = "There was an error starting the export: " \
        "#{export.errors.full_messages.to_sentence}"
    end

    redirect_to sponsorable_dashboard_fiscal_host_path(sponsorable)
  end

  private

  sig { returns T.nilable(Sponsors::StripePayoutInput) }
  memoize def payout_input
    Sponsors::StripePayoutInput.deserialize(params[:payout])
  end

  sig { returns T.nilable(String) }
  memoize def payout_id
    payout_input&.payout_id
  end

  sig { returns T.nilable(Billing::StripeConnect::Account) }
  memoize def stripe_account
    stripe_account_id = payout_input&.account_id
    if stripe_account_id
      Billing::StripeConnect::Account.find_by(stripe_account_id: stripe_account_id)
    else
      sponsorable_sponsors_listing&.active_stripe_connect_account
    end
  end

  sig { returns(T.any(Symbol, GitHubSponsors::Types::Sponsorable)) }
  def target_for_conditional_access
    sponsorable || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  sig { returns(T::Array[Billing::Stripe::Payout]) }
  memoize def stripe_payouts
    sponsorable_sponsors_listing&.stripe_payouts_sorted_by_created || []
  end

  sig { returns(T::Boolean) }
  def stripe_payouts_success?
    sponsorable_sponsors_listing&.stripe_connect_accounts.present? || stripe_payouts.any?
  end
end
