# typed: true
# frozen_string_literal: true

module DependencyReview
  class Manifest
    attr_reader :path, :type, :vulnerable_dependencies, :added_dependencies, :removed_dependencies, :updated_dependencies, :dependencies

    def initialize(path:, type:)
      @path = path
      @type = type
      @dependencies = []
      @added_dependencies = []
      @removed_dependencies = []
      @updated_dependencies = []
      @vulnerable_dependencies = []
    end

    def add_dependency(dependency, change_type)
      @dependencies.push(dependency)
      case change_type
      when :added
        @added_dependencies.push(dependency)
      when :removed
        @removed_dependencies.push(dependency)
      when :updated
        @updated_dependencies.push(dependency)
      end
    end

    def add_vulnerable_dependency(dependency)
      if !@vulnerable_dependencies.include? dependency
        @vulnerable_dependencies.push(dependency)
      end
    end

    def sort_dependencies
      #sort priority is vulnerable first, then additions, updates, then removals, and then alphabetical

      # alphabetical sorting
      [@added_dependencies, @updated_dependencies, @removed_dependencies, @vulnerable_dependencies].each do |change_type|
        change_type.sort_by! { |dep| dep.package_name }
      end

      #change type sorting for non-vulnerable dependencies
      change_type_sorted_dependencies = @added_dependencies + @updated_dependencies + @removed_dependencies

      non_vuln_dependencies = change_type_sorted_dependencies - @vulnerable_dependencies
      @vulnerable_dependencies = sorted_vulnerable_dependencies
      @dependencies = @vulnerable_dependencies + non_vuln_dependencies
    end

    def sorted_vulnerable_dependencies
      return [] if @vulnerable_dependencies.blank?

      # change type sorting
      change_type_order = { added: 0, updated: 1, removed: 2 }
      @vulnerable_dependencies.sort_by! { |d| change_type_order[d.change_type] }

      # max severity sorting
      severity_weights = { "critical": 0, "high": 1, "moderate": 2, "low": 3 }

      weighted_dependencies = @vulnerable_dependencies.map do |dependency|
        #ensure vulns are sorted by severities
        dependency.sort_severities

        weighted_vulnerabilites = fetch_severities(dependency).map { |severity| severity_weights[severity.to_sym] }
        weight = weighted_vulnerabilites.empty? ? severity_weights["low"] : weighted_vulnerabilites.min
        { dependency: dependency, weight: weight }
      end

      weighted_dependencies.sort_by! { |d| d[:weight] }
      weighted_dependencies.map { |d| d[:dependency] }
    end

    def fetch_severities(dependency)
      dependency&.vulnerabilities.map { |vuln| vuln.severity }
    end

    def self.from_twirp(twirp_manifest)
      manifest = Manifest.new(path: twirp_manifest.file_path, type: twirp_manifest.type)
      twirp_manifest.dependencies.each do |twirp_dependency|
        Dependency.from_twirp(manifest, twirp_dependency)
      end
      manifest
    end
  end
end
