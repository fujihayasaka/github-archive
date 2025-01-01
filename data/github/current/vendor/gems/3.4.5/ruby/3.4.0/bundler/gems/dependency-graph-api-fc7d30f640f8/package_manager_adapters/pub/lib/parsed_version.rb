# frozen_string_literal: true

require_relative "requirements"
require_relative "utilities"

module Pub
  class ParsedVersion
    include Logging

    # NOTES: things pub.dev API does not expose that we want to capture:
    # - license metadata
    # - author & contact info
    # - explicit source code URL (we make best-effort using docs and homepage meta)
    # - unpublished (removed/yanked package) indicator

    attr_reader :package_name, :package_version, :package_manager, :description
    attr_reader :home_url, :source_url, :docs_url, :dependencies, :published_at, :unpublished_at

    def initialize(package_name:, raw_version:, description:, source_url:, home_url:, docs_url:,
                   raw_dependencies:, raw_published_at:, raw_unpublished_at: nil)
      @package_name = package_name
      @package_version = raw_version
      @package_manager = Pub::PACKAGE_MANAGER
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

    private

    def resolve_dependencies(raw_deps)
      resolved = []
      raw_deps.each do |dep|
          version = resolve_version(raw_version: dep[:raw_version], package_name: dep[:package_name])
          resolved << {
            scope: dep[:raw_scope],
            requirements: version,
            package_name: dep[:package_name],
          } unless version.nil?
      end

      resolved
    end

    # Parse the version requirements spec (Pub format) into a well-formed
    # transitive package dependency version or range bounds in DG format.
    # Args:
    # - raw_version:  the Pub-style version requirements
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
