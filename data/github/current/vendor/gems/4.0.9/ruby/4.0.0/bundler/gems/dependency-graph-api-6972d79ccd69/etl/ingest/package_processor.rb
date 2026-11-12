# frozen_string_literal: true

module Ingest
  class PackageProcessor < Processor
    def initialize(name: "package_release", debug: false)
      super
    end

    def consume_message(message)
      package = create_package_release(message.value.with_indifferent_access)

      Rails.env.development? ? LoadPackageJob.perform_now(package) : LoadPackageJob.perform_later(package)

      # Enqueue backfill job for npm packages to catch missing versions
      if npm_backfill_enabled? && package.package_manager == Types::PackageManager[:npm] && !Rails.env.development?
        BackfillPackageJob.perform_later(package.package_manager.name, package.package_name)
      end
    end

    def npm_backfill_enabled?
      ActiveModel::Type::Boolean.new.cast(ENV["NPM_BACKFILL_ENABLED"] || "true")
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
