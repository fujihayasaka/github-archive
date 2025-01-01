# typed: strict
# frozen_string_literal: true

class ExportSponsorsDependenciesJob < ApplicationJob
  extend T::Sig

  queue_as :sponsors_dependencies_export

  locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC

  retry_on_dirty_exit

  sig do
    params(
      org: Organization,
      actor: User,
    ).void
  end
  def perform(org:, actor:)
    GitHub.logger.info("ExportSponsorsDependenciesJob perform")
    return unless GitHub.sponsors_enabled?
    return unless GitHub.flipper[:sponsors_org_dependencies].enabled?(org)

    export = Sponsors::SponsorshipsDependenciesExport.new(
      org: org,
      viewer: actor,
    )

    GitHub.logger.info("ExportSponsorsDependenciesJob export")

    SponsorsPrimerMailer.sponsors_dependencies_export(
      filename: export.filename,
      mime_type: "text/csv",
      export_content: export.csv,
      actor: actor,
    ).deliver_now
  end
end
