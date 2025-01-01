# typed: true
# frozen_string_literal: true

module DependencyReview
  class ReviewSummary
    attr_reader :added_dependencies, :removed_dependencies, :updated_dependencies, :manifests, :page_metadata, :snapshot_warnings
    attr_accessor :vulnerable_dependencies

    def initialize(manifests:, page_metadata: nil, snapshot_warnings: [])
      @manifests = manifests
      @added_dependencies = @manifests.map { |m| m.added_dependencies }.flatten
      @removed_dependencies = @manifests.map { |m| m.removed_dependencies }.flatten
      @updated_dependencies = @manifests.map { |m| m.updated_dependencies }.flatten
      @vulnerable_dependencies = []
      @page_metadata = page_metadata
      @snapshot_warnings = snapshot_warnings
    end

    # Public: Find a manifest by path
    #   path - String
    #
    # Returns DependencyReview::Manifest
    def find_manifest(path)
      manifests.find { |m| m.path == path }
    end

    def has_changes?
      @added_dependencies.count > 0 || @removed_dependencies.count > 0 || @updated_dependencies.count > 0
    end

    def load_vulnerabilities(vulnerability_loader:, decompose_updates: false)
      all_vvr_ids = {}
      all_deps_to_check = [added_dependencies, updated_dependencies]
      all_deps_to_check.push(removed_dependencies) if decompose_updates
      all_deps_to_check.flatten!

      all_deps_to_check.each do |dependency|
        next unless dependency.github_vulnerability_range_ids.present?
        dependency.github_vulnerability_range_ids.each { |range_id| all_vvr_ids[range_id] = nil }
      end

      vulnerabilities = vulnerability_loader.get_all_vulnerabilities_for_range_ids(all_vvr_ids.keys)
      all_deps_to_check.each do |dependency|
        dependency.apply_vulnerabilities(vulnerabilities)
      end
      @vulnerable_dependencies = @manifests.map { |m| m.vulnerable_dependencies }.flatten
    end

    def sort_dependencies
      @manifests.each { |manifest| manifest.sort_dependencies }
    end

    def self.from_twirp(snapshot_diff)
      manifests = snapshot_diff.changed_manifests.map do |twirp_manifest|
        Manifest.from_twirp(twirp_manifest)
      end

      page_metadata = snapshot_diff.page_metadata ? PageMetadata.from_twirp(snapshot_diff.page_metadata) : nil

      self.new(manifests: manifests, page_metadata: page_metadata, snapshot_warnings: snapshot_diff.snapshot_warnings)
    end
  end
end
