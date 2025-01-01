# typed: strict
# frozen_string_literal: true

class Sponsors::Payouts::ReceiptsController < ApplicationController
  extend T::Sig
  include Sponsors::AdminableControllerValidations

  before_action :require_acceptance_into_sponsors_program
  before_action :non_waitlisted_sponsors_listing_required
  before_action :require_listing_to_support_payout_receipts
  before_action :require_stripe_connect_account_or_payout_year, only: :create

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  stylesheet_bundle :sponsors

  sig { void }
  def index
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end
    stripe_payouts_sorted_by_created = listing.stripe_payouts_sorted_by_created
    total_paid_out_by_year = listing.total_paid_out_by_year
    sponsorable = T.must_because(self.sponsorable) { "#non_waitlisted_sponsors_listing_required ensures non-nil" }
    tax_id = sponsorable.sponsor_sales_tax_vat_id
    include_layout = !request.xhr?

    render "sponsors/payouts/receipts/index", locals: {
      stripe_payouts_sorted_by_created: stripe_payouts_sorted_by_created,
      total_paid_out_by_year: total_paid_out_by_year,
      sponsors_listing: listing,
      tax_id: tax_id,
      include_layout: include_layout,
    }, layout: include_layout
  end

  sig { void }
  def create
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end

    tax_id = params[:tax_id]
    address1 = params[:address1]
    address2 = params[:address2]

    if params[:payout_year].present?
      receipt = SponsorsListing::Receipt.for_listing_and_year(
        sponsors_listing: listing,
        year: params[:payout_year].to_i,
        tax_id: tax_id,
        sponsorable_address1: address1,
        sponsorable_address2: address2,
      )
    else
      stripe_payout_id = params[:payout_id]
      stripe_account = T.must_because(stripe_connect_account) do
        "#require_stripe_connect_account_or_payout_year ensures non-nil"
      end
      payout_response = stripe_account.load_payout(stripe_payout_id)
      unless payout_response.success?
        flash[:error] = "Could not load payout #{stripe_payout_id} for Stripe account #{stripe_account}"
        return redirect_to(sponsorable_dashboard_payouts_path(sponsorable))
      end

      payout = payout_response.result
      receipt = SponsorsListing::Receipt.for_payout(
        sponsors_listing: listing,
        tax_id: tax_id,
        stripe_payout: payout,
        sponsorable_address1: address1,
        sponsorable_address2: address2,
        start_date: payout_start_date,
      )
    end

    send_data receipt.as_pdf, filename: receipt.pdf_filename, type: "application/pdf"
  end

  private

  sig { returns(DateTime) }
  def payout_start_date
    start_date_from_params = params[:payout_start_date_unix]
    start_date_in_unix = start_date_from_params.to_i if start_date_from_params
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end

    if start_date_in_unix.blank?
      accepted_at = listing.accepted_at
      return accepted_at.utc.to_datetime if accepted_at
      return T.must(listing.created_at).utc.to_datetime
    end

    parsed_start_date = Time.at(start_date_in_unix).utc
    (parsed_start_date.beginning_of_day + 1.day).to_datetime
  end

  sig { void }
  def require_listing_to_support_payout_receipts
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end
    render_404 unless listing.supports_payout_receipts?
  end

  sig { returns T.nilable(Billing::StripeConnect::Account) }
  memoize def stripe_connect_account
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end
    listing.stripe_connect_accounts.find_by(stripe_account_id: params[:stripe_account_id])
  end

  sig { void }
  def require_stripe_connect_account_or_payout_year
    render_404 unless stripe_connect_account || params[:payout_year].present?
  end

  sig { returns T.any(Symbol, GitHubSponsors::Types::Sponsorable) }
  def target_for_conditional_access
    target_sponsorable = sponsorable
    return :no_target_for_conditional_access unless target_sponsorable # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    target_sponsorable
  end
end
