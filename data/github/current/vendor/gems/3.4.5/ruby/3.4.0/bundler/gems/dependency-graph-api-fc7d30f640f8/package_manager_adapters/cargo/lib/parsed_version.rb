# frozen_string_literal: true

require_relative "requirements"
require_relative "utilities"

module Cargo
  class ParsedVersion
    include Logging

    # max license string length we store from any source
    LICENSE_SIZE_LIMIT = 255

    attr_reader :package_name, :package_version, :package_manager, :authors, :download_count, :description
    attr_reader :home_url, :source_url, :docs_url, :dependencies, :published_at, :unpublished_at

    def initialize(package_name:, raw_version:, authors:, license:, download_count:, description:,
                   source_url:, home_url:, docs_url:, raw_dependencies:, raw_published_at:, raw_unpublished_at: nil)
      @package_name = package_name
      @package_version = raw_version
      @package_manager = Cargo::PACKAGE_MANAGER
      @authors = authors
      @download_count = download_count
      @license = license
      @description = description
      @source_url = source_url
      @docs_url = docs_url
      @home_url = home_url
      @dependencies = resolve_dependencies(raw_dependencies)
      @published_at = raw_published_at.to_time.to_i     # DateTime => UNIX timestamp
      @unpublished_at = raw_unpublished_at.to_time.to_i if raw_unpublished_at # DateTime => UNIX timestamp
    end

    def to_hash
      {
        value: {
          package_name: package_name,
          package_version: package_version,
          package_manager: package_manager,
          authors: authors,
          download_count: download_count,
          license: license,
          description: description,
          published_at: published_at,
          unpublished_at: unpublished_at,
          source_url: source_url,
          docs_url: docs_url,
          home_url: home_url,
          dependencies: dependencies.compact,
        }.reject { |key, value| value.to_s.empty? }.compact.to_json
      }
    end

    def license
      @license.to_s[0...LICENSE_SIZE_LIMIT]
    end

    private

    def resolve_dependencies(raw_deps)
      resolved = []
      raw_deps.each do |dep|
          version = resolve_version(raw_version: dep[:raw_version], package_name: dep[:package_name])
          scope = dep[:raw_scope] == 0 ? :runtime : :development
          resolved << { scope: scope, requirements: version, package_name: dep[:package_name] } if !version.nil?
      end

      resolved
    end

    # Parse the version requirements spec (Cargo format) into a well-formed
    # transitive package dependency version or range bounds in DG format.
    # Args:
    # - raw_version:  the Cargo-style version requirements
    # - package_name: the package name for context when logging ephemeral parse errors
    # Returns:
    # - DG-formatted version requirements (or empty string)
    # - boolean value indicating the parse failed
    def resolve_version(raw_version:, package_name:)
      resolved_version, invalid = Requirements::parse(raw_version)

      # if we can't resolve version range on a transitive dependency
      # of a package release, it's not a show-stopper
      if invalid || resolved_version.nil? || resolved_version.empty?
        logger.error("package #{package_name} failed parsing version requirements: #{raw_version}")
        return ""
      end

      resolved_version
    end
  end
end
