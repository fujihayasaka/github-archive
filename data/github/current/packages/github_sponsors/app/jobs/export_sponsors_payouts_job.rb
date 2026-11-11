# typed: true
# frozen_string_literal: true

class ExportSponsorsPayoutsJob < ApplicationJob
  queue_as :sponsors_payouts_export

  # Sponsorable user or organization ID
  locked_by timeout: 1.hour, key: ->(job) { job.arguments[0].id }

  retry_on_dirty_exit

  class SponsorsPayoutsExportError < StandardError; end

  # sponsorable - Organization that has a SponsorsListing that's marked as a fiscal host
  # actor - optional User who requested the export
  # payout_id - String ID of the Stripe::Payout to export
  # recipient - optional User who should receive the export email; defaults to the sponsorable if omitted
  # stripe_account - optional Billing::StripeConnect::Account related to the payout_id, defaults to the sponsorable's
  #                  currently active Stripe account if omitted
  sig do
    params(
      sponsorable: GitHubSponsors::Types::Sponsorable,
      actor: T.nilable(User),
      payout_id: T.nilable(String),
      recipient: T.nilable(User),
      stripe_account: T.nilable(Billing::StripeConnect::Account),
    ).void
  end
  def perform(sponsorable, actor: nil, payout_id: nil, recipient: nil, stripe_account: nil)
    return unless GitHub.sponsors_enabled?

    export = SponsorsListing::PayoutsExport.new(
      sponsors_listing: sponsorable.sponsors_listing,
      payout_id: payout_id,
      stripe_account: stripe_account,
    )

    return unless valid_export?(export)

    SponsorsPrimerMailer.payouts_export(
      sponsorable: sponsorable,
      filename: export.filename,
      export_content: export.as_csv,
      actor: actor,
      recipient: recipient,
    ).deliver_later
  end

  private

  def valid_export?(export)
    return true if export.valid?

    err = "There was an error starting the export: #{export.errors.full_messages.to_sentence}"
    Failbot.report(
      SponsorsPayoutsExportError.new(err),
      app: "github-sponsors",
      sponsorable_login: export.sponsorable_login,
      payout_id: export.payout_id,
    )
  end
end
