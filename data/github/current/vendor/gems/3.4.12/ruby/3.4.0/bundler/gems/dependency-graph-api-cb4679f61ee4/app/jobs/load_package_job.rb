# frozen_string_literal: true

class LoadPackageJob < RetryJob
  queue_as :package

  def perform(package)
    loader = Ingest::PackageLoader.new(package)
    loader.load
    Instrument.increment("etl.ingest.processed",
      stage: "packages",
      package_manager: package.package_manager
    )
  end

  rescue_from(StandardError) do |exception|
    Failbot.report(exception,
      "gh.aqueduct.queue.name" => queue_name,
      "gh.aqueduct.job.name" => "etl.load_package_job"
    )
  end
end
