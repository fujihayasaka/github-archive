# typed: strict
# frozen_string_literal: true

class ExportSponsorsSponsorshipsJob < ApplicationJob
  extend T::Sig

  queue_as :sponsors_sponsorships_export

  locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC

  retry_on_dirty_exit

  sig do
    params(
      sponsor: GitHubSponsors::Types::Sponsor,
      active: T::Boolean,
      actor: User,
    ).void
  end
  def perform(sponsor, active:, actor:)
    GitHub.logger.info("ExportSponsorsSponsorshipsJob perform")
    return unless GitHub.sponsors_enabled?

    export = Sponsors::SponsorshipsExport.new(
      sponsor: sponsor,
      active: active
    )

    SponsorsPrimerMailer.sponsors_sponsorships_export(
      sponsor: sponsor,
      filename: export.filename,
      mime_type: "text/csv",
      export_content: export.csv,
      actor: actor,
    ).deliver_later
  end
end
