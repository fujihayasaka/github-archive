# typed: true
# frozen_string_literal: true

class ExportSponsorsTransactionsJob < ApplicationJob
  queue_as :sponsors_transactions_export

  locked_by timeout: 1.hour, key: ->(job) { job.arguments[0].id }

  retry_on_dirty_exit

  # sponsorable - an Organization that has a SponsorsListing that's marked as a fiscal host
  # timeframe - String or Symbol representing how much transaction history to export; choose between :month or :all
  # actor - the User who requested this export; optional
  # recipient - optional User who should receive the export email; defaults to the `contact_email_address` of the
  #             SponsorsListing if not specified
  def perform(sponsorable, timeframe:, actor: nil, recipient: nil)
    return unless GitHub.sponsors_enabled?

    listing = sponsorable.sponsors_listing
    return unless listing&.fiscal_host?

    export = SponsorsListing::TransactionsExport.new(sponsors_listing: listing, timeframe: timeframe)

    SponsorsPrimerMailer.sponsors_transactions_export(
      sponsorable: sponsorable,
      filename: export.filename,
      mime_type: "text/csv",
      export_content: export.as_csv,
      description: export.all_time? ? "all time" : "the last month",
      actor: actor,
      recipient: recipient,
    ).deliver_later
  end
end
