require "set"

module Snapshots
  class SnapshotDiffModel
    attr_reader :base_sha, :target_sha, :changed_manifests, :github_repository_id
    attr_writer :snapshot_warnings

    def initialize(github_repository_id:, base_sha:, target_sha:, changed_manifests:, dependency_snapshot: false, page_metadata: nil, snapshot_warnings: [])
      @github_repository_id = github_repository_id
      @base_sha = base_sha
      @target_sha = target_sha
      @changed_manifests = changed_manifests
      @vulnerable_build_dependencies = {}
      @build_dependency_metadata = {}
      @dependency_snapshot = dependency_snapshot
      @page_metadata = page_metadata
      @snapshot_warnings = snapshot_warnings
    end

    def to_twirp
      DependencyGraphAPI::V1::GetSnapshotsDiffResponse.new(
        repository_id: @github_repository_id,
        base_sha: @base_sha,
        target_sha: @target_sha,
        changed_manifests: @changed_manifests.map(&:to_twirp),
        page_metadata: @page_metadata,
        # TODO this is still pretty fake
        base_sha_created_at: Time.now - 600, # i.e., minus 10 minutes
        target_sha_created_at: Time.now,
        snapshot_warnings: @snapshot_warnings
      )
    end

    def to_dependency_snapshot_twirp
      vuln_mapping = {}
      @vulnerable_build_dependencies.each do |purl, vuln_range_id_set|
        vuln_mapping[purl] = {
          github_vulnerability_range_ids: vuln_range_id_set.to_a
        }
      end

      DependencyGraphAPI::V1::GetDependencySnapshotsDiffResponse.new(
        changed_manifests: @changed_manifests.map(&:to_dependency_snapshot_twirp),
        vulnerable_dependencies: vuln_mapping,
        dependency_metadata: @build_dependency_metadata
      )
    end

    def load_page_metadata(metadata)
      @page_metadata = {
        page: metadata[:page],
        per_page: metadata[:per_page],
        first: metadata[:first],
        last: metadata[:last],
      }
    end

    # when we are decomposing updates, we need vulnerabilities on `removed` changes as well
    # as `added` changes.
    def load_vulnerabilities(decompose_updates: false)
      GitHub::Telemetry.tracer.in_span("load_vulnerabilities") do
        change_buckets_by_manifest_type = {}
        @changed_manifests.each do |manifest|
          my_deps = if decompose_updates
                      manifest.dependencies
                    else
                      manifest.dependencies.select { |dependency| dependency.change_type == :added || dependency.change_type == :updated }
                    end

          my_deps.each do |dependency|
            package_manager = dependency.ecosystem || manifest.package_manager
            change_buckets_by_manifest_type[package_manager] ||= []
            change_buckets_by_manifest_type[package_manager].push dependency
          end
        end

        change_buckets_by_manifest_type.each do |package_manager, changes|
          if package_manager.equal?(:unknown)
            unless @dependency_snapshot
              # unknown/unsupported package manager
              DependencyGraph.logger.warn("Unknown package manager",
                "gh.repo.id" => @github_repository_id,
                "gh.dependency_graph.snapshot.base_sha" => @base_sha,
                "gh.dependency_graph.snapshot.target_sha" => @target_sha
              )
            end

            next
          end

          changes.flatten!
          dependencies_by_name = changes.group_by { |x| x.name.downcase }
          service_package_manager = Types::PackageManager[package_manager]
          names_to_look_for = dependencies_by_name.keys

          scoped_ranges = ::VulnerableVersionRange
                            .for_package_manager(service_package_manager)
                            .for_package(names_to_look_for)
                            .select(:id, :package_name, :version_range, :github_id)

          scoped_ranges.find_in_batches do |batch_of_ranges|
            batch_of_ranges.each do |range|
              vuln_for_package_name = range.package_name.downcase
              dependencies = dependencies_by_name[vuln_for_package_name]

              if dependencies.blank?
                DependencyGraph.logger.warn("Vulnerability range does not match expected package name",
                  "gh.repo.id" => @github_repository_id,
                  "gh.dependency_graph.snapshot.base_sha" => @base_sha,
                  "gh.dependency_graph.snapshot.target_sha" => @target_sha,
                  "gh.dependency_graph.package.name" => vuln_for_package_name
                )
                next
              end

              if @dependency_snapshot
                load_dependency_snapshot_vuln_ids(range: range, dependencies: dependencies, ecosystem: service_package_manager)
              else
                load_snapshot_vuln_ids(range: range, dependencies: dependencies, ecosystem: service_package_manager, decompose_updates: decompose_updates)
              end
            end
          end
        end
      end
    end

    def load_metadata
      GitHub::Telemetry.tracer.in_span("load_metadata") do
        if @dependency_snapshot
          load_dependency_snapshot_metadata
        else
          load_snapshot_metadata
        end
      end
    end

    def get_key_for_release_lookup(package_manager, package_name, version)
      [package_manager, package_name, version].join("|")
    end

    private

    def find_metadata_by_batch_coords(coords:)
      package_releases = PackageRelease.find_metadata_by_batch_coords(coords)
      package_releases.map do |release|
        [get_key_for_release_lookup(release.package_manager, release.package_name, release.name) , release]
      end.to_h
    end

    def load_snapshot_metadata
      coords = []
      changed_manifests.each do |manifest|
        manifest.dependencies.each do |dependency|
          next unless dependency.target_version_exact.present? || dependency.base_version_exact.present?

          coords.push({
                        package_name: dependency.name,
                        package_manager: Types::PackageManager[manifest.package_manager],
                        package_version: dependency.target_version_exact || dependency.base_version_exact
                      })
        end
      end

      releases_lookup = find_metadata_by_batch_coords(coords: coords)

      changed_manifests.each do |manifest|
        manifest.dependencies.each do |dependency|
          version = dependency.target_version_exact || dependency.base_version_exact
          package_release = releases_lookup[get_key_for_release_lookup(manifest.package_manager, dependency.name, version)]

          if package_release
            dependency.update_metadata_from_package_release(package_release)
            next if dependency.github_repository_id.present? || dependency.repo_nwo.present?
          end

            # fall back to higher level package data if we can't find a release
            # examples: requirements string has no exact version, package release has no repo info
          package = Package.find_by(package_manager: Types::PackageManager[manifest.package_manager], name: dependency.name)
          dependency.update_metadata_from_package(package) if package
        end
      end
    end

    def load_dependency_snapshot_metadata
      coords = []
      changed_manifests.each do |manifest|
        manifest.dependencies.each do |dependency|
          # skip unknown package managers
          next unless Types::PackageManager.recognized? manifest.package_manager

          package_manager = Types::PackageManager[manifest.package_manager]
          next unless package_manager.present?

          coords.push({
                        package_name: dependency.name,
                        package_manager: package_manager,
                        package_version: dependency.target_purl&.version || dependency.base_purl&.version
                      })
        end
      end

      releases_lookup = find_metadata_by_batch_coords(coords: coords)

      changed_manifests.each do |manifest|
        manifest.dependencies.each do |dependency|
          package_url = dependency.target_purl || dependency.base_purl
          package_release = releases_lookup[get_key_for_release_lookup(manifest.package_manager, dependency.name, package_url.version)]
          next unless package_release.present?

          @build_dependency_metadata[package_url.to_purl] = {
            license: package_release.license,
            repo_nwo: package_release.repository_nwo,
            github_repository_id: package_release.github_repository_id,
            published_at: package_release.published_at&.comparable_time
          }
        end
      end
    end

    def load_snapshot_vuln_ids(range:, dependencies:, ecosystem: nil, decompose_updates: false)
      dependencies.each do |dependency_request|

        # added: target_version = 1, base_version = nil
        # remove: target_version = nil, base_version = 1
        # updated: target_version = 2, base_version = 1

        requirements = []

        if !dependency_request.target_version.blank?
          target_requirement = Versioning::RequirementSet.deserialize(dependency_request.target_version, allow_named_versions: Types::PackageManager.allows_named_versions?(ecosystem))
          requirements.push(target_requirement)
        end

        if decompose_updates && !dependency_request.base_version.blank?
          base_requirement = Versioning::RequirementSet.deserialize(dependency_request.base_version, allow_named_versions: Types::PackageManager.allows_named_versions?(ecosystem))
          requirements.push(base_requirement)
        end

        requirements.each do |requirement|
          next unless requirement.valid?
          if range.requirements_set.contain?(requirement)
            dependency_request.github_vulnerability_range_ids.push(range.github_id)
          end
        end
      end
    end

    def load_dependency_snapshot_vuln_ids(range:, dependencies:, ecosystem: nil)
      dependencies.each do |dependency_request|
        target_purl = dependency_request.target_purl
        requirement = Versioning::RequirementSet.deserialize("=#{target_purl.version}", allow_named_versions: Types::PackageManager.allows_named_versions?(ecosystem))
        next unless requirement.valid?
        if range.requirements_set.contain?(requirement)
          existing_vulns = @vulnerable_build_dependencies[target_purl.to_purl] || Set.new
          existing_vulns.add(range.github_id)
          @vulnerable_build_dependencies[target_purl.to_purl] = existing_vulns
        end
      end
    end
  end

  class ManifestDiffModel
    attr_reader :file_path, :dependencies, :package_manager

    def initialize(file_path:, package_manager:, dependencies:)
      @file_path = file_path
      @package_manager = package_manager
      @dependencies = dependencies || []
    end

    def to_twirp
      DependencyGraphAPI::V1::GetSnapshotsDiffResponse::ManifestDiff.new(
        type: Types::PackageManager[package_manager].to_proto,
        file_path: @file_path,
        dependencies: @dependencies.sort_by(&:name).map(&:to_twirp)
      )
    end

    def to_dependency_snapshot_twirp
      DependencyGraphAPI::V1::GetDependencySnapshotsDiffResponse::DependencySnapshotManifestDiff.new(
        type: Types::PackageManager[package_manager].to_proto,
        file_path: @file_path,
        dependencies: @dependencies.map(&:to_dependency_snapshot_twirp)
      )
    end
  end

  class DependencyDiffModel
    attr_reader :target_version, :base_version, :name, :change_type, :github_vulnerability_range_ids, :license, :repo_nwo,
      :github_repository_id, :published_at, :unpublished_at, :ecosystem, :scope

    def initialize(name:, change_type:, scope:, target_version: nil, base_version: nil, ecosystem: nil, target_purl: nil, base_purl: nil)
      raise ArgumentError if target_version.nil? && base_version.nil?
      @name = name
      @target_version = target_version
      @target_version_requirements = parse_requirements(target_version)
      @base_version = base_version
      @base_version_requirements = parse_requirements(base_version)
      @change_type = change_type
      @github_vulnerability_range_ids = []
      @ecosystem = ecosystem
      @scope = scope

      @exact_base_version_or_range = exact_version_or_fallback(@base_version_requirements, @base_version)
      @exact_target_version_or_range = exact_version_or_fallback(@target_version_requirements, @target_version)

      @base_purl = base_purl || generate_purl(@exact_base_version_or_range)
      @target_purl = target_purl || generate_purl(@exact_target_version_or_range)
    end

    def to_twirp
      DependencyGraphAPI::V1::GetSnapshotsDiffResponse::ManifestDiff::DependencyDiff.new(
        name: @name,
        base_version: @exact_base_version_or_range,
        target_version: @exact_target_version_or_range,
        change_type: twirp_change_type,
        github_vulnerability_range_ids: github_vulnerability_range_ids,
        license: @license,
        repo_nwo: @repo_nwo,
        github_repository_id: @github_repository_id,
        published_at: @published_at.present? ? @published_at.comparable_time : nil,
        unpublished_at: @unpublished_at.present? ? @unpublished_at.comparable_time : nil,
        dependent_count: @dependent_count,
        base_purl: @base_purl,
        target_purl: @target_purl,
        scope: twirp_scope,
      )
    end

    def twirp_scope
      case scope.to_sym
      when :runtime
        DependencyGraphAPI::V1::Scope::SCOPE_RUNTIME
      when :development
        DependencyGraphAPI::V1::Scope::SCOPE_DEVELOPMENT
      when :unknown
        DependencyGraphAPI::V1::Scope::SCOPE_UNKNOWN
      end
    end

    def twirp_change_type
      case change_type
      when :added
        DependencyGraphAPI::V1::GetSnapshotsDiffResponse::ManifestDiff::DependencyDiff::DependencyChangeType::DEPENDENCY_CHANGE_TYPE_ADDED
      when :removed
        DependencyGraphAPI::V1::GetSnapshotsDiffResponse::ManifestDiff::DependencyDiff::DependencyChangeType::DEPENDENCY_CHANGE_TYPE_REMOVED
      when :updated
        DependencyGraphAPI::V1::GetSnapshotsDiffResponse::ManifestDiff::DependencyDiff::DependencyChangeType::DEPENDENCY_CHANGE_TYPE_UPDATED
      end
    end

    def generate_purl(version)
      return nil if ecosystem.blank? || name.blank?
      version = "" if version.nil?

      # for now, only create purls for plain version strings
      version = "" unless version.match(Versioning::VersionParser::SEMANTIC_PATTERN) || Types::PackageManager.allows_named_versions?(ecosystem)
      PackageUrls::PackageUrl.from_package_release(package_manager: ecosystem, name: name, version: version).to_purl
    end

    def base_version_exact
      exact_version = if version_only?(@base_version)
                        @base_version
                      else
                        @base_version_requirements.exact_version
                      end

      return exact_version.present? ? exact_version : nil
    end

    def target_version_exact
      exact_version = if version_only?(@target_version)
                        @target_version
                      else
                        @target_version_requirements.exact_version
                      end

      return exact_version.present? ? exact_version : nil
    end

    def exact_version_or_fallback(requirements, fallback)
      return fallback unless requirements.present?
      return fallback unless requirements.exact_version.present?
      return requirements.exact_version
    end

    # sometimes, we ingest a requirements string that is just a version with no `=`,
    # so let's make sure we let it be a valid exact version
    def version_only?(version_string)
      return false if version_string.blank?
      version_string.match?(Versioning::VersionParser::SEMANTIC_PATTERN) || Versioning::GenericVersionParser.valid_named_version?(Types::PackageManager.allows_named_versions?(ecosystem), version_string)
    end

    def parse_requirements(requirements)
      Versioning::RequirementSet.deserialize(requirements, allow_named_versions: Types::PackageManager.allows_named_versions?(ecosystem),
        on_error: -> (invalid) {
          Instrument.increment("snapshot_diff.invalid_requirements",
            invalid_range: invalid,
            context: {
              snapshot_stage: "model_translation"
            },
            allow_named_versions: Types::PackageManager.allows_named_versions?(ecosystem),
          )
        }
      )
    end

    def update_metadata_from_package_release(package_release)
      @license = package_release.license
      @repo_nwo = package_release.repository_nwo
      @github_repository_id = package_release.github_repository_id
      @published_at = package_release.published_at
      @unpublished_at = package_release.unpublished_at
      @dependent_count = package_release.dependent_count
    end

    def update_metadata_from_package(package)
      @repo_nwo = package.repository_nwo # TODO: Known bug where repo id is updated but nwo is not, should we just use github repo id to pull repo object for reliablity?
      @github_repository_id = package.repository_id # yes, this is the github_repository_id
    end
  end

  class BuildDependencyDiffModel
    attr_reader :change_type, :base_purl, :target_purl, :name, :base_scope, :target_scope

    def initialize(change_type:, base_purl: nil, target_purl: nil, base_scope: nil, target_scope: nil)
      raise ArgumentError if base_purl.nil? && target_purl.nil?
      @name = base_purl&.name || target_purl&.name
      @base_purl = base_purl
      @target_purl = target_purl
      @change_type = change_type
      @base_scope = base_scope
      @target_scope = target_scope
    end

    def to_dependency_snapshot_twirp
      # it doesn't matter which purl, this is just to help client identify the general package
      purl = base_purl || target_purl

      DependencyGraphAPI::V1::GetDependencySnapshotsDiffResponse::DependencySnapshotManifestDiff::DependencySnapshotDependencyDiff.new(
        package: [purl.type, purl.full_package_name].join,
        base: {
          purl: @base_purl&.to_purl,
          scope: @base_scope
        },
        target: {
          purl: @target_purl&.to_purl,
          scope: @target_scope
        }
      )
    end
  end
  end
