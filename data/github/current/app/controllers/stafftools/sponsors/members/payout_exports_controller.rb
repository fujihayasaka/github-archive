# typed: strict
# frozen_string_literal: true

class Stafftools::Sponsors::Members::PayoutExportsController < Stafftools::SponsorsController
  extend T::Sig

  layout "application"

  before_action :require_fiscal_host

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
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
    render Sponsors::Payouts::ExportFormComponent.new(
      stripe_payouts: stripe_payouts,
      form_url: stafftools_sponsors_member_payout_exports_path(this_listing.sponsorable_login),
      success: stripe_payouts_success?,
      sponsorable_login: this_listing.sponsorable_login,
    ), layout: false
  end

  sig { void }
  def create
    export = SponsorsListing::PayoutsExport.new(
      sponsors_listing: this_listing,
      payout_id: payout_id,
      stripe_account: stripe_account
    )

    if export.start_export_job(actor: current_user, recipient: current_user)
      flash[:notice] = "We've started exporting #{this_sponsorable}'s payout information " \
        "You'll receive an email at #{current_user.email} shortly with the export attached."
    else
      flash[:error] = "There was an error starting the export: " \
        "#{export.errors.full_messages.to_sentence}"
    end

    redirect_to stafftools_sponsors_member_path(this_sponsorable)
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
      this_listing.active_stripe_connect_account
    end
  end

  sig { void }
  def require_fiscal_host
    unless this_listing.fiscal_host?
      flash[:error] = "You can only export payouts for fiscal hosts."
      redirect_to stafftools_sponsors_member_path(this_sponsorable)
    end
  end

  sig { returns(T::Array[Billing::Stripe::Payout]) }
  memoize def stripe_payouts
    this_listing.stripe_payouts_sorted_by_created || []
  end

  sig { returns(T::Boolean) }
  def stripe_payouts_success?
    this_listing.stripe_connect_accounts.present? || stripe_payouts.any?
  end
end
