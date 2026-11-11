# typed: true
# frozen_string_literal: true

class ExportSponsorableMaintainersJob < ApplicationJob
  retry_on_dirty_exit

  queue_as :sponsors_explore_export

  # One export with the same arguments per hour
  locked_by timeout: 1.hour, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  # viewer - the User who requested the export
  # sort_by - optional String indicating how to sort the sponsorable maintainers; choose from
  #           `SponsorsHelper::MAINTAINER_SORT_OPTIONS` keys
  # org - optional Organization whose repositories' dependencies will be checked for sponsorable maintainers;
  #       if omitted, the viewer's repositories will be checked; the viewer must have permission to load the org's
  #       sponsorable dependencies
  # ecosystems - optional Array of String ecosystems (package managers) to filter which dependencies are included;
  #              see `Platform::Enums::DependencyGraphEcosystem` for valid values
  # direct_only - Boolean indicating whether only the account's direct dependencies should be included, versus both
  #               direct and indirect dependencies; an indirect dependency is one that the owner isn't using
  #               in one of their own repos, but rather is a dependency of a dependency
  def perform(viewer:, sort_by: nil, org: nil, ecosystems: [], direct_only: true)
    return unless GitHub.sponsors_enabled? && viewer
    return if viewer.no_verified_emails?
    return if org && !viewer.can_load_sponsorable_dependencies_for?(org)

    filter_set = SponsorsExploreFilterSet.new(
      sort_by: sort_by,
      ecosystems: ecosystems,
      direct_only: direct_only,
      account_login: org&.login,
    )
    explore_loader = SponsorsExploreLoader.new(filter_set: filter_set, viewer: viewer, org: org)
    exporter = Sponsors::ExploreExporter.new(
      explore_loader: explore_loader,
      filter_set: filter_set,
      viewer: viewer,
    )
    SponsorsPrimerMailer.sponsorable_maintainers_export(
      recipient: viewer,
      filename: exporter.filename,
      mime_type: "text/csv",
      export_content: exporter.to_csv,
      org: org,
      explore_params: filter_set.query_args,
    ).deliver_now
  end
end
