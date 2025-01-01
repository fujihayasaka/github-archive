# typed: true
# frozen_string_literal: true

module DependencyGraph
  class PackageReleaseVulnerabilitiesQuery < Query
    VULNERABILITIES_FILTERS = {
      package_manager: {
        arg: :packageManager,
        type: :enum,
      },
      package_name: {
        arg: :packageName,
      },
      contains_version: {
        arg: :containsVersion,
      },
    }

    def initialize(vulnerabilities_filter:, backend: nil)
      @vulnerabilities_filter = vulnerabilities_filter
      super(backend: backend)
    end

    def results
      execute_query.map do |response|
        response["data"]["packageReleaseVulnerabilities"]
      end
    end

    def query(options = {})
      field(:packageReleaseVulnerabilities, {
        arguments: map_arguments(VULNERABILITIES_FILTERS, @vulnerabilities_filter),
      }.merge(options))
    end
  end
end
