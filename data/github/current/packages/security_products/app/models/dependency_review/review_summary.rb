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
    sig { params(path: String).returns(T.nilable(Manifest)) }
    def find_manifest(path)
      manifests.find { |m| m.path == path }
    end

    sig { returns(T::Boolean) }
    def has_changes?
      !@added_dependencies.empty? || !@removed_dependencies.empty? || !@updated_dependencies.empty?
    end

    sig { params(include_innersource: T::Boolean, decompose_updates: T::Boolean).void }
    def load_vulnerabilities(include_innersource:, decompose_updates: false)
      all_vvr_ids = {}
      all_deps_to_check = [added_dependencies, updated_dependencies]
      all_deps_to_check.push(removed_dependencies) if decompose_updates
      all_deps_to_check.flatten!

      all_deps_to_check.each do |dependency|
        next unless dependency.github_vulnerability_range_ids.present?
        dependency.github_vulnerability_range_ids.each { |range_id| all_vvr_ids[range_id] = nil }
      end

      vulnerabilities = get_all_vulnerabilities_for_range_ids(all_vvr_ids.keys, include_innersource)
      all_deps_to_check.each do |dependency|
        dependency.apply_vulnerabilities(vulnerabilities)
      end
      @vulnerable_dependencies = @manifests.map { |m| m.vulnerable_dependencies }.flatten
    end

    sig { void }
    def sort_dependencies
      @manifests.each { |manifest| manifest.sort_dependencies }
    end

    sig { params(snapshot_diff: T.untyped).returns(ReviewSummary) }
    def self.from_twirp(snapshot_diff)
      manifests = snapshot_diff.changed_manifests.map do |twirp_manifest|
        Manifest.from_twirp(twirp_manifest)
      end

      page_metadata = snapshot_diff.page_metadata ? PageMetadata.from_twirp(snapshot_diff.page_metadata) : nil

      self.new(manifests: manifests, page_metadata: page_metadata, snapshot_warnings: snapshot_diff.snapshot_warnings)
    end

    private

    # sig { params(range_ids: T::Array[Integer], include_innersource: T::Boolean).returns(T::Hash[Integer, DependencyReview::Vulnerability]) }
    def get_all_vulnerabilities_for_range_ids(range_ids, include_innersource)
      hash_of_vvr_id_to_vulns = {}
      vvr_id_to_vuln = DependencyGraph::VulnerabilitiesQuery.vulnerabilities_for_range_ids(range_ids: range_ids, include_innersource: include_innersource)
      vvr_id_to_vuln.each do |vrr_id, content|
        hash_of_vvr_id_to_vulns[vrr_id] = DependencyReview::Vulnerability.new(
          severity: content[:advisory].severity,
          vulnerable_version_range: content[:vulnerability].requirements,
          first_patched_version: content[:vulnerability].fixed_in,
          advisory_ghsa_id: content[:advisory].ghsa_id,
          advisory_summary: content[:advisory].summary,
          advisory_description: content[:advisory].description)
      end

      hash_of_vvr_id_to_vulns
    end
  end
end
