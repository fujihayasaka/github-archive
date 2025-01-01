# typed: true
# frozen_string_literal: true

module DependencyReview
  class Dependency
    CHANGE_TYPE_MAPPINGS = {
      DEPENDENCY_CHANGE_TYPE_UNKNOWN: :unknown,
      DEPENDENCY_CHANGE_TYPE_ADDED: :added,
      DEPENDENCY_CHANGE_TYPE_REMOVED: :removed,
      DEPENDENCY_CHANGE_TYPE_UPDATED: :updated,
    }.freeze
    TWIRP_CHANGE_TYPES = CHANGE_TYPE_MAPPINGS.keys.freeze

    SCOPE_MAPPINGS = {
      SCOPE_UNKNOWN: :unknown,
      SCOPE_RUNTIME: :runtime,
      SCOPE_DEVELOPMENT: :development,
    }

    attr_reader :package_name, :version, :license, :repo_nwo, :repo_url, :published_at, :dependents_count, :manifest, :is_vulnerable, :change_type, :vulnerabilities, :github_vulnerability_range_ids, :repo_id, :purl, :scope

    def initialize(package_name:, version:, change_type:, manifest:, license:, repo_nwo:, published_at:, repo_id:, dependents_count:, repo_url: nil, purl: nil, scope: nil, github_vulnerability_range_ids: nil)
      @package_name = package_name
      @version = todo_cleanup_version(version)
      @dependents_count = dependents_count
      @license = license
      @repo_nwo = repo_nwo
      @repo_url = repo_url
      @published_at = convert_to_date_time(published_at)
      @manifest = manifest
      @change_type = change_type
      @repo_id = repo_id
      @repo_url = repo_nwo.present? ? URI.join(GitHub.url, repo_nwo).to_s : nil
      @purl = purl
      @scope = scope
      manifest.add_dependency(self, change_type)
      @vulnerabilities = []
      @github_vulnerability_range_ids = github_vulnerability_range_ids.to_a
    end

    def is_vulnerable?
      @github_vulnerability_range_ids.present?
    end

    def apply_vulnerabilities(vvr_ids_to_vulnerabilities)
      return unless @github_vulnerability_range_ids.present?
      @github_vulnerability_range_ids.each do |github_vvr_id|
        vulnerability = vvr_ids_to_vulnerabilities[github_vvr_id]
        next unless vulnerability.present?

        manifest.add_vulnerable_dependency(self)
        @vulnerabilities.push(vulnerability)
      end
    end

    def sort_severities
      return unless self.is_vulnerable?

      severities = { critical: 0, high: 1, moderate: 2, low: 3 }
      @vulnerabilities.sort_by! { |v| severities[v.severity.to_sym] }
    end

    def todo_cleanup_version(version)
      # this hack shouldn't hurt anything, generally, but is in place because we have surprising data coming in version field
      return version if version.nil?
      version = version.dup.strip
      version[0] = "" if version[0] == "="
      version.strip
    end

    def convert_to_date_time(proto_date_time)
      return nil if proto_date_time.nil?
      proto_date_time.to_time.to_datetime
    end

    def self.from_twirp(manifest_model, twirp_dependency)
      # removed manifests have a different shape for dependencies, we have to infer their dependency diffs
      should_use_target_version = defined?(twirp_dependency.target_version) && !twirp_dependency.target_version.empty?
      version = should_use_target_version ? twirp_dependency.target_version : twirp_dependency.base_version

      should_use_target_purl = defined?(twirp_dependency.target_purl) && !twirp_dependency.target_purl.empty?
      purl = should_use_target_purl ? twirp_dependency.target_purl : twirp_dependency.base_purl

      dependency_change_type = defined?(twirp_dependency.change_type) ? get_change_type(twirp_dependency.change_type) : :removed
      dependency_scope = defined?(twirp_dependency.scope) ? get_scope(twirp_dependency.scope) : :unknown

      Dependency.new(
        package_name: twirp_dependency.name,
        version: version,
        change_type: dependency_change_type,
        manifest: manifest_model,
        github_vulnerability_range_ids: twirp_dependency.try(:github_vulnerability_range_ids),
        license: twirp_dependency.try(:license),
        repo_nwo: twirp_dependency.try(:repo_nwo),
        published_at: twirp_dependency.try(:published_at),
        repo_id: twirp_dependency.try(:github_repository_id),
        dependents_count: twirp_dependency.try(:dependent_count) || 0,
        purl: purl,
        scope: dependency_scope,
      )
    end

    def self.get_change_type(twirp_change_type)
      raise ArgumentError unless TWIRP_CHANGE_TYPES.include?(twirp_change_type)

      CHANGE_TYPE_MAPPINGS[twirp_change_type]
    end

    def self.get_scope(twirp_scope)
      SCOPE_MAPPINGS[twirp_scope] || :unknown
    end
  end
end
