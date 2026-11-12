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

    # Filter out dependencies from non-lockfile manifests when a corresponding
    # lockfile exists in the same directory. This prevents double-reporting of
    # dependencies that appear in both a primary manifest (e.g., Gemfile) and
    # its lockfile (e.g., Gemfile.lock).
    #
    # Dependencies that are unique to the primary manifest (not in the lockfile)
    # are preserved.
    def filter_superseded_dependencies!
      # Group manifests by directory
      manifests_by_directory = @changed_manifests.group_by do |manifest|
        dir = File.dirname(manifest.file_path)
        dir == "." ? "" : dir
      end

      # Get superseding cases mapping from Types::Manifest
      superseding_map = Types::Manifest.superseding_cases

      filtered_manifests = []

      manifests_by_directory.each do |directory, manifests|
        # Build a map of manifest type to manifest for this directory
        manifest_by_type = {}
        manifests.each do |manifest|
          # Determine the manifest type from the file path using ManifestAdapters
          filename = File.basename(manifest.file_path)
          path = manifest.file_path

          begin
            manifest_type = ManifestAdapters.manifest_type(filename: filename, path: path)
            manifest_by_type[manifest_type.id] = manifest
          rescue ManifestAdapters::NotRecognizedError
            # Unknown manifest type - keep it as-is
            filtered_manifests << manifest
          end
        end

        # For each manifest, check if it's superseded by another manifest in the same directory
        manifest_by_type.each do |type_id, manifest|
          superseding_type_ids = superseding_map[type_id]

          if superseding_type_ids && superseding_type_ids.any? { |id| manifest_by_type.key?(id) }
            # This manifest is superseded by a lockfile in the same directory
            # Get the superseding manifest(s)
            superseding_manifests = superseding_type_ids.map { |id| manifest_by_type[id] }.compact

            # Get all dependency names from the superseding manifests
            superseding_dep_names = superseding_manifests.flat_map { |m| m.dependencies.map(&:name) }.to_set

            # Filter out dependencies that are also in the superseding manifest
            unique_deps = manifest.dependencies.reject { |dep| superseding_dep_names.include?(dep.name) }

            # Only keep this manifest if it has unique dependencies
            if unique_deps.any?
              filtered_manifest = ManifestDiffModel.new(
                file_path: manifest.file_path,
                package_manager: manifest.package_manager,
                dependencies: unique_deps
              )
              filtered_manifests << filtered_manifest
            end
          else
            # Not superseded, keep the manifest as-is
            filtered_manifests << manifest
          end
        end
      end

      @changed_manifests = filtered_manifests
    end

    # when we are decomposing updates, we need vulnerabilities on `removed` changes as well
    # as `added` changes.
    def load_vulnerabilities(decompose_updates: false, business_id: nil, org_id: nil)
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
                            .visible_to(business_id: business_id, org_id: org_id)
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

    # Determines the package manager for a dependency, either from the manifest
    # or by extracting it from the dependency's PURL for unknown manifest types.
    # Returns nil if the package manager cannot be determined.
    def package_manager_for_dependency(manifest:, dependency:, package_url_obj: nil)
      if Types::PackageManager.recognized?(manifest.package_manager) && manifest.package_manager != :unknown
        # For recognized manifests, use the manifest package manager directly
        manifest.package_manager
      elsif package_url_obj.present?
        # If a PackageUrl object is provided, use it to determine the package manager
        package_url_obj.type_dg_api.name
      else
        # For unknown manifests, parse the PURL and extract the ecosystem
        package_url = dependency.target_purl || dependency.base_purl
        return nil unless package_url.present?

        package_url_obj = PackageUrls::PackageUrl.from_purl(purl: package_url)
        package_url_obj.type_dg_api.name
      end
    end

    def find_metadata_by_batch_coords(coords:)
      package_releases = PackageRelease.find_metadata_by_batch_coords(coords)
      package_releases.map do |release|
        [get_key_for_release_lookup(release.package_manager, release.package_name, release.name) , release]
      end.to_h
    end

    def load_snapshot_metadata
      coords = []
      total_dependencies = 0
      changed_manifests.each do |manifest|
        manifest.dependencies.each do |dependency|
          next unless dependency.target_version_exact.present? || dependency.base_version_exact.present?

          package_manager = package_manager_for_dependency(manifest: manifest, dependency: dependency)

          # Skip if we still can't determine the package manager or if it's unknown
          next unless package_manager.present?

          package_manager_type = Types::PackageManager[package_manager]

          version_variants = PackageReleaseSearchAdapter.version_tuples_for_query(
            package_manager_type,
            dependency.target_version_exact || dependency.base_version_exact
          )

          version_variants.each do |version|
            coords.push({
              package_name: dependency.name,
              package_manager: package_manager_type,
              package_version: version
            })
          end
        end
      end

      releases_lookup = find_metadata_by_batch_coords(coords: coords)

      batch_hits = 0
      changed_manifests.each do |manifest|
        manifest.dependencies.each do |dependency|
          total_dependencies += 1
          version = dependency.target_version_exact || dependency.base_version_exact

          package_manager = package_manager_for_dependency(manifest: manifest, dependency: dependency)
          next unless package_manager.present?

          package_manager_type = Types::PackageManager[package_manager]

          version_variants = PackageReleaseSearchAdapter.version_tuples_for_query(
            package_manager_type,
            version
          )

          # Use package_manager symbol for hash lookup (to match what comes from the database)
          package_release = nil
          version_variants.each do |variant|
            package_release ||= releases_lookup[get_key_for_release_lookup(package_manager, dependency.name, variant)]
          end

          if package_release
            batch_hits += 1
            dependency.update_metadata_from_package_release(package_release)
          end
        end
      end

      # Emit instrumentation metrics
      Instrument.histogram("snapshot_diff.load_metadata.total_dependencies", total_dependencies, source: "manifest")
      Instrument.histogram("snapshot_diff.load_metadata.batch_coords_count", coords.size, source: "manifest")
      Instrument.histogram("snapshot_diff.load_metadata.batch_hits", batch_hits, source: "manifest")
    end

    def load_dependency_snapshot_metadata
      coords = []
      changed_manifests.each do |manifest|
        manifest.dependencies.each do |dependency|
          package_url = dependency.target_purl || dependency.base_purl
          next unless package_url.present?

          package_url_obj = PackageUrls::PackageUrl.from_purl(purl: package_url)
          package_manager = package_manager_for_dependency(manifest: manifest, dependency: dependency, package_url_obj: package_url_obj)

          # Skip if we still can't determine the package manager or if it's unknown
          next unless package_manager.present?

          coords.push({
                        package_name: dependency.name,
                        package_manager: Types::PackageManager[package_manager],
                        package_version: package_url_obj.version
                      })
        end
      end

      releases_lookup = find_metadata_by_batch_coords(coords: coords)

      total_dependencies = 0
      batch_hits = 0
      changed_manifests.each do |manifest|
        manifest.dependencies.each do |dependency|
          total_dependencies += 1
          package_url = dependency.target_purl || dependency.base_purl
          next unless package_url.present?

          package_url_obj = PackageUrls::PackageUrl.from_purl(purl: package_url)
          package_manager = package_manager_for_dependency(manifest: manifest, dependency: dependency, package_url_obj: package_url_obj)
          next unless package_manager.present?

          # Use package_manager symbol for hash lookup (to match what comes from the database)
          package_release = releases_lookup[get_key_for_release_lookup(package_manager, dependency.name, package_url_obj.version)]
          next unless package_release.present?

          batch_hits += 1
          dependency.update_metadata_from_package_release(package_release)

          @build_dependency_metadata[package_url_obj.to_purl] = {
            license: package_release.license,
            repo_nwo: package_release.repository_nwo,
            github_repository_id: package_release.github_repository_id,
            published_at: package_release.published_at&.comparable_time
          }
        end
      end

      # Emit instrumentation metrics
      Instrument.histogram("snapshot_diff.load_metadata.total_dependencies", total_dependencies, source: "dependency_snapshot")
      Instrument.histogram("snapshot_diff.load_metadata.batch_coords_count", coords.size, source: "dependency_snapshot")
      Instrument.histogram("snapshot_diff.load_metadata.batch_hits", batch_hits, source: "dependency_snapshot")
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
      :github_repository_id, :published_at, :unpublished_at, :ecosystem, :scope, :target_purl, :base_purl

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
