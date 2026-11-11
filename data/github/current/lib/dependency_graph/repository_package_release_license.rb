# typed: true
# frozen_string_literal: true

# Public: Domain object to wrap the license stats for repository package releases.
module DependencyGraph
  class RepositoryPackageReleaseLicense
    def self.wrap(licenses)
      licenses.map { |attrs| new(attrs) }
    end

    def initialize(attrs)
      @attrs = attrs
    end

    def license_id
      attrs["license"]
    end

    def total_count
      attrs["totalCount"]
    end

    attr_reader :attrs
  end
end
