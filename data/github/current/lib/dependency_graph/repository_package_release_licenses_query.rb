# typed: true
# frozen_string_literal: true

module DependencyGraph
  class RepositoryPackageReleaseLicensesQuery < Query
    TIMEOUT = 10.0

    FILTERS = {
      owner_ids: {
        arg: :ownerIds,
        type: :array,
      },
      package_manager: {
        arg: :packageManager,
        type: :enum,
      },
      package_name: {
        arg: :name,
      },
      package_version: {
        arg: :version,
      },
      exact_match: {
        arg: :exactMatch,
        type: :boolean,
      },
      only_vulnerable_packages: {
        arg: :vulnerable,
        type: :boolean,
      },
      severity: {
        arg: :severity,
        type: :enum,
      },
      preview: {
        arg: :preview,
        type: :boolean,
      },
    }

    def self.default_backend
      @default_backend ||= ::DependencyGraph::Client.new(connection: DependencyGraph::Client.default_connection, timeout: TIMEOUT)
    end

    def initialize(release_filter:, backend: nil)
      @release_filter = release_filter
      super(backend: backend)
    end

    def results
      response = execute_query.value!
      licenses = response["data"]["repositoryPackageReleases"]["licenses"]
      RepositoryPackageReleaseLicense.wrap(licenses)
    end

    def query(options = {})
      field(:repositoryPackageReleases, {
        arguments: map_arguments(FILTERS, @release_filter),
        selections: [
          field(:licenses, {
            selections: [
              field(:license),
              field(:totalCount),
            ],
          }),
        ],
      }.merge(options))
    end
  end
end
