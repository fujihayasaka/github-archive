# frozen_string_literal: true

class LoadPackageJob < RetryJob
  queue_as :package

  def perform(package)
    if should_skip_job?(package)
      Instrument.increment("etl.ingest.skip_job",
        stage: "packages",
        package_manager: package.package_manager.to_s
      )
      return
    end

    loader = Ingest::PackageLoader.new(package)
    loader.load

    Instrument.increment("etl.ingest.processed",
      stage: "packages",
      package_manager: package.package_manager
    )
  end

  # If the release is a npm package, we can skip processing the job if the package
  # source_url or unpublished_at has not changed.
  # This is kind of a hack, but the volume of NPM package is so high that we would
  # benefit from skipping processing jobs that we know will not change the data in a significant way.
  def should_skip_job?(release)
    return false unless release.package_manager == Types::PackageManager[:npm]

    existing_release = ActiveRecord::Base.connected_to(role: :reading) do
      PackageRelease
        .where(package_name: release.package_name, package_manager: release.package_manager, name: release.version)
        .limit(1)
        .pluck(:source_url, :unpublished_at)
        .first
    end

    # If the package has been unpublished, or the source_url has changed, then we can skip
    # processing the job
    existing_release.present? &&
      existing_release[0] == release.source_url &&
      existing_release[1] == release.unpublished_at
  rescue StandardError => e
    Failbot.report(e)
    return false
  end

  rescue_from(StandardError) do |exception|
    Failbot.report(exception,
      "gh.aqueduct.queue.name" => queue_name,
      "gh.aqueduct.job.name" => "etl.load_package_job"
    )
  end
end
