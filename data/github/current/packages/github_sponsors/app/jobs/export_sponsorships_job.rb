# typed: strict
# frozen_string_literal: true

class ExportSponsorshipsJob < ApplicationJob
  queue_as :sponsorships_export

  locked_by timeout: 1.hour, key: ->(job) { job.arguments[0].id }

  retry_on_dirty_exit

  class SponsorshipsExportError < StandardError; end

  sig do
    params(
      sponsorable: GitHubSponsors::Types::Sponsorable,
      year: T.nilable(T.any(String, Integer)),
      month: T.nilable(T.any(Symbol, String)),
      format: T.any(String, Symbol),
      timeframe: T.nilable(String),
      actor: T.nilable(User)
    ).void
  end
  def perform(sponsorable, year:, month:, format:, timeframe:, actor:)
    return unless GitHub.sponsors_enabled?

    sponsors_listing = sponsorable.sponsors_listing
    return unless sponsors_listing

    export = SponsorsListing::SponsorshipsExport.new(
      sponsors_listing: sponsors_listing,
      year: year,
      month: month,
      format: format,
      timeframe: timeframe,
    )

    if !export.valid?
      report_error(export, sponsorable)
      return
    end

    instrument_export(sponsorable, actor)

    SponsorsPrimerMailer.sponsorships_export(
      sponsorable: sponsorable,
      filename: export.filename,
      mime_type: export.mime_type,
      export_content: export.fetch_content,
      description: export.description,
      actor: actor,
    ).deliver_later
  end

  private

  sig { params(export: SponsorsListing::SponsorshipsExport, sponsorable: GitHubSponsors::Types::Sponsorable).void }
  def report_error(export, sponsorable)
    err = "There was an error starting the export: #{export.errors.full_messages.to_sentence}"
    Failbot.report(
      SponsorshipsExportError.new(err),
      app: "github-sponsors",
      sponsorable_login: sponsorable.login,
      export_format: export.format,
      export_year: export.year,
      export_month: export.month,
      timeframe: export.timeframe,
    )
  end

  sig { params(sponsorable: GitHubSponsors::Types::Sponsorable, actor: T.nilable(User)).void }
  def instrument_export(sponsorable, actor)
    GlobalInstrumenter.instrument("sponsors.sponsorship_transactions_export", {
      listing: sponsorable.sponsors_listing,
      sponsorable: sponsorable,
      actor: actor,
    })
  end
end
