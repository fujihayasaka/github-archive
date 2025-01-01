# frozen_string_literal: true

module Ingest
  class PackageProcessor < Processor
    def initialize(name: "package_release", debug: false)
      super
    end

    def consume_message(message)
      package = create_package_release(message.value.with_indifferent_access)

      if should_skip_job?(package)
        Instrument.increment("package_processor.skip_job", package_manager: package.package_manager.to_s)
        return
      end

      Rails.env.development? ? LoadPackageJob.perform_now(package) : LoadPackageJob.perform_later(package)
    end

    # If the package is an npm package, we can skip processing the job if the package
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
      return existing_release.present? &&
              existing_release[0] == release.source_url &&
              existing_release[1] == release.unpublished_at
    rescue StandardError => e
      Failbot.report(e)
      return false
    end

    def consume_debug_message(message)
      puts message.inspect
    end

    def create_package_release(message)
      Packages::PackageRelease.new(
        package_manager: Types::PackageManager.coerce(message[:package_manager]),
        package_name: message[:package_name],
        namespace: message[:namespace],
        version: message[:package_version],
        description: message[:description],
        authors: message[:authors],
        download_count: message[:download_count],
        external_id: message[:external_id],
        source_url: message[:source_url],
        home_url: message[:home_url],
        docs_url: message[:docs_url],
        license: message[:license],
        published_at: (Time.at(message[:published_at]) if message[:published_at]),
        unpublished_at: (Time.at(message[:unpublished_at]) if message[:unpublished_at].nonzero?),
        dependencies: message[:dependencies].map do |dependency|
          Packages::PackageRelease::Dependency.new(
            package_name: dependency[:package_name],
            requirements: dependency[:requirements],
            scope: Types::Scope.coerce(dependency[:scope].empty? ? Types::Scope[:runtime].to_s : dependency[:scope])
          )
        end
      )
    end
  end
end
