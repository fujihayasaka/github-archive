module RepositoryDependenciesService
  module V1
    class Search
      include DependencyGraph::Tracing

      attr_reader :dependencies_client, :dgp_available

      def initialize(req, dependencies_client:, dgp_insights_client:, dgp_available:)
        @req = req
        @dependencies_client = dependencies_client
        @dgp_insights_client = dgp_insights_client
        @dgp_available = dgp_available
      end

      def run
        # A list of package managers for which we are sourcing dependencies from
        # DGP instead of DG-API.
        #
        # In GHES environments, we default this to an empty set since DGP is not available in that
        # environment.
        #
        # TODO: When we add another ecosystem to DGP, we should parameterize supported_by_dgp to accept repository_id
        #
        # The list of package managers supported by DGP should be filtered down by feature flag for on a per-ecosystem
        # basis to allow us to dark-ship new ones without affecting existing DGP users while still maintaining a
        # GHES circuit breaker at this point in the code.
        package_managers_from_dgp = dgp_available ? Types::PackageManager.supported_by_dgp : []

        requested_package_managers = @req.ecosystem_filter.map { |e| Types::PackageManager.from_proto(e) { Types::PackageManager[:unknown] } }

        all_package_managers = if requested_package_managers.present?
                                 requested_package_managers
                               else
                                 # If package manager filter is unspecified on request, then request all package managers
                                 Types::PackageManager.to_a
                               end

        # Package managers for which dependencies will be sourced from DGP, after
        # the package manager filter is applied.
        package_managers_from_dgp = all_package_managers & package_managers_from_dgp
        # Package managers for which dependencies will be sourced from DG-API, after
        # the package manager filter is applied.
        package_managers_from_dg_api = all_package_managers - package_managers_from_dgp
        package_managers_from_ds_api = all_package_managers

        if @req.has_relationship_filter?
          # Dirty trick: if the request has a relationship filter, we don't want to get any dependencies
          # from DG-API, but we still want to get the filter values for package_manager, which
          # are currently fetched in the search_ds_dependencies and search_dg_api_dependencies functions.
          package_managers_from_dg_api = []
        end

        vulnerable_dependencies = @req.dependabot_alerts.map { |da|
          [da.vulnerable_manifest_path, da.vulnerable_version_range_affects, da.vulnerable_requirements].map(&:downcase)
        }.to_set

        result_set = ResultSet.empty
        exclude_manifest_filepaths = Set.new

        result_set = result_set.merge(search_ds_dependencies(
          query: @req.query,
          included_dependencies: vulnerable_dependencies,
          manifest_path: @req.manifest_path,
          package_managers: package_managers_from_ds_api
        ))
        exclude_manifest_filepaths = result_set.manifest_paths

        # Get VulnerableVersionRanges from dependabot alerts that'll be sent over to DGP
        dgp_vvrs = dgp_vvrs_from_dependabot_alerts(
          dependabot_alerts: @req.dependabot_alerts,
          package_managers: package_managers_from_dgp
        )

        result_set = result_set.merge(search_dgp_dependencies(
          repository_id: @req.repository_id,
          package_name_filter: @req.query,
          vulnerability_filter: :VULNERABILITY_FILTER_VULNERABLE,
          package_managers: package_managers_from_dgp,
          relationship_filter: @req.has_relationship_filter? ? @req.relationship_filter : nil,
          vulnerable_version_ranges: dgp_vvrs,
          exclude_manifest_filepaths: exclude_manifest_filepaths
        ))

        result_set = result_set.merge(search_dg_dependencies(
          repository_id: @req.repository_id,
          query: @req.query,
          included_dependencies: vulnerable_dependencies,
          manifest_path: @req.manifest_path,
          package_managers: package_managers_from_dg_api,
          exclude_manifest_filepaths: exclude_manifest_filepaths
        ))

        result_set = sort_result_set(result_set)

        base_offset = (@req.page - 1) * @req.per_page
        base_limit = @req.per_page
        result_set.results = result_set.results.slice(base_offset, base_limit) || []

        result_set = result_set.merge(search_ds_dependencies(
          query: @req.query,
          offset: [base_offset - result_set.total_results, 0].max,
          limit: base_limit - result_set.results.length,
          excluded_dependencies: vulnerable_dependencies,
          manifest_path: @req.manifest_path,
          package_managers: package_managers_from_ds_api
        ))

        result_set = result_set.merge(search_dgp_dependencies(
          repository_id: @req.repository_id,
          package_name_filter: @req.query,
          vulnerability_filter: :VULNERABILITY_FILTER_NOT_VULNERABLE,
          pagination: {
            offset: [base_offset - result_set.total_results, 0].max,
            limit: base_limit - result_set.results.length
          },
          package_managers: package_managers_from_dgp,
          relationship_filter: @req.has_relationship_filter? ? @req.relationship_filter : nil,
          vulnerable_version_ranges: dgp_vvrs,
          exclude_manifest_filepaths: exclude_manifest_filepaths
        ))

        result_set = result_set.merge(search_dg_dependencies(
          repository_id: @req.repository_id,
          query: @req.query,
          offset: [base_offset - result_set.total_results, 0].max,
          limit: base_limit - result_set.results.length,
          excluded_dependencies: vulnerable_dependencies,
          manifest_path: @req.manifest_path,
          package_managers: package_managers_from_dg_api,
          exclude_manifest_filepaths: exclude_manifest_filepaths
        ))

        result_set.load_repository_ids
        result_set.load_licenses

        root_ancestors = get_root_ancestors_for_dgp_dependencies(
          repository_id: @req.repository_id,
          dependency_ids: result_set.results.select(&:scanned_by_dgp?).map(&:id)
        )
        result_set.load_root_ancestors(
          root_ancestors: root_ancestors,
        )

        result_set
      end

      def repository_has_snapshots
        snapshot_manifests.present?
      end

      def search_dgp_dependencies(
        repository_id:,
        package_name_filter:,
        pagination: nil,
        package_managers: [],
        relationship_filter: nil,
        vulnerable_version_ranges: [],
        vulnerability_filter: nil,
        exclude_manifest_filepaths: nil
      )
        if package_managers.empty?
          return ResultSet.new(total_results: 0, results: [], package_managers: [])
        end

        relationship = case relationship_filter
                       when :RELATIONSHIP_UNKNOWN, :RELATIONSHIP_INCONCLUSIVE
                         :RELATIONSHIP_UNKNOWN
                       else
                         relationship_filter
                       end

        if exclude_manifest_filepaths.present? && exclude_manifest_filepaths.any?
          exclude_manifest_filepaths = exclude_manifest_filepaths.map { |p| DependencyGraph::ObjectModel::AbstractManifest.normalize_manifest_path(p) }
        end

        response = @dgp_insights_client.get_dependencies_for_repository(
          repository_id: repository_id,
          package_name_filter: package_name_filter,
          pagination: pagination,
          exclude_manifest_filepaths: exclude_manifest_filepaths.to_a,
          vulnerability_filter: vulnerability_filter,
          vulnerable_version_ranges: vulnerable_version_ranges,
          relationship_filter: relationship,
          ecosystem_filter: package_managers.map { |pm| pm.dgp_ecosystem.to_sym }
        )

        DependencyGraph.logger.info("Repo Insights DGP get_dependencies_for_repository response", response: response.data.to_json)

        ResultSet.new(
          total_results: response.data.total_dependencies,
          package_managers: response.data.ecosystems.map { |e| Types::PackageManager.by(:dgp_ecosystem, e) { Types::PackageManager[:unknown] } }.uniq,
          results: response.data.dependencies.map do |d|
            Result.new(
              id: d.id,
              package_manager: Types::PackageManager.by(:dgp_ecosystem, d.ecosystem) { Types::PackageManager[:unknown] },
              package_name: d.package_name,
              requirements: d.requirements,
              manifest_path: d.manifest_path,
              scanned_by: :DGP,
              scanned_at: d.scanned_at,
              relationship: d.relationship,
              vulnerable_version_range_ids: d.vulnerable_version_range_ids.to_a,
              license: d.package_license
            )
          end
        )
      end

      def search_dg_dependencies(
        repository_id:,
        query:,
        offset: nil,
        limit: nil,
        included_dependencies: nil,
        excluded_dependencies: nil,
        manifest_path: nil,
        package_managers: [],
        exclude_manifest_filepaths: nil
      )
        ActiveRecord::Base.connected_to(role: :reading) do
          if DependencyGraph.use_normalized_tables?
            return search_normalized_dg_dependencies(repository_id:, query:, offset:, limit:, included_dependencies:, excluded_dependencies:, manifest_path:, package_managers:, exclude_manifest_filepaths:)
          end
          search_denormalized_dg_dependencies(repository_id:, query:, offset:, limit:, included_dependencies:, excluded_dependencies:, manifest_path:, package_managers:, exclude_manifest_filepaths:)
        end
      end

      def search_denormalized_dg_dependencies(
        repository_id:,
        query:,
        offset: nil,
        limit: nil,
        included_dependencies: nil,
        excluded_dependencies: nil,
        manifest_path: nil,
        package_managers: nil,
        exclude_manifest_filepaths: nil
      )
        repo = Repository.find_by(github_repository_id: repository_id)
        return ResultSet.empty if repo.nil?

        manifests_scope = Manifest.where(repository: repo)

        unless preview_enabled?
          manifests_scope = manifests_scope.where.not(manifest_type: preview_manifest_type).where.not(package_manager: preview_package_manager)
        end

        repo_package_managers = manifests_scope.distinct.pluck(:package_manager).map { |pm| Types::PackageManager.by(:id, pm) }

        manifests_scope = manifests_scope.where(package_manager: package_managers)

        if manifest_path.present?
          path, filename = split_manifest_path(manifest_path)
          manifests_scope = manifests_scope.where("coalesce(#{Manifest.table_name}.path, '') = ?", path).where(filename: filename)
        end

        if exclude_manifest_filepaths.present? && exclude_manifest_filepaths.any?
          normalized_manifest_paths = exclude_manifest_filepaths.map { |p| normalize_manifest_path_for_db(p) }
          manifests_scope = manifests_scope.where.not(
            "concat(coalesce(#{Manifest.table_name}.path, ''), '/', #{Manifest.table_name}.filename) IN (?)",
            normalized_manifest_paths
          )
        end

        manifests_by_id = manifests_scope
                            .select(:id, :manifest_type, :path, :filename, :last_pushed_at)
                            .map { |m| [m.id, m] }.to_h

        dependencies_rel = ManifestDependency.latest_revisions.without_superseded_in_repository.merge(manifests_scope)

        if query.present?
          dependencies_rel = dependencies_rel.where(
            "package_name LIKE ?",
            "%" + ActiveRecord::Base.sanitize_sql_like(query.downcase.strip) + "%"
          )
        end

        unless included_dependencies.nil?
          dependencies_rel = dependencies_rel.where_in(
            ["#{Manifest.table_name}.path", "#{Manifest.table_name}.filename", "package_name", "requirements"],
            included_dependencies.map { |manifest_path, *rest| [*split_manifest_path(manifest_path), *rest] }
          )
        end

        unless excluded_dependencies.nil?
          dependencies_rel = dependencies_rel.where_not_in(
            ["#{Manifest.table_name}.path", "#{Manifest.table_name}.filename", "package_name", "requirements"],
            excluded_dependencies.map { |manifest_path, *rest| [*split_manifest_path(manifest_path), *rest] }
          )
        end

        dependencies = dependencies_rel
                         .order(manifest_id: :asc, package_name: :asc, requirements: :asc)
                         .select(:id, :manifest_id, :package_name, :requirements)

        if offset.present?
          dependencies = dependencies.offset(offset)
        end

        if limit.present?
          dependencies = dependencies.limit(limit)
        end

        ResultSet.new(
          total_results: dependencies_rel.count,
          package_managers: repo_package_managers,
          results: dependencies.map do |d|
            manifest = manifests_by_id[d.manifest_id]
            Result.new(
              package_manager: manifest.manifest_type.package_manager,
              package_name: d.package_name,
              requirements: d.requirements,
              manifest_path: manifest.full_path,
              scanned_by: :DG,
              scanned_at: manifest.last_pushed_at.utc
            )
          end
        )
      end

      def search_normalized_dg_dependencies(
        repository_id:,
        query:,
        offset: nil,
        limit: nil,
        included_dependencies: nil,
        excluded_dependencies: nil,
        manifest_path: nil,
        package_managers: nil,
        exclude_manifest_filepaths: nil
      )
        repo = Repository.find_by(github_repository_id: repository_id)
        return ResultSet.empty if repo.nil?

        manifests_scope = Manifest.where(repository: repo)

        unless preview_enabled?
          manifests_scope = manifests_scope.where.not(manifest_type: preview_manifest_type).where.not(package_manager: preview_package_manager)
        end

        repo_package_managers = manifests_scope.distinct.pluck(:package_manager).map { |pm| Types::PackageManager.by(:id, pm) }

        manifests_scope = manifests_scope.where(package_manager: package_managers)

        if manifest_path.present?
          path, filename = split_manifest_path(manifest_path)
          manifests_scope = manifests_scope.where("coalesce(#{Manifest.table_name}.path, '') = ?", path).where(filename: filename)
        end

        if exclude_manifest_filepaths.present? && exclude_manifest_filepaths.any?
          normalized_manifest_paths = exclude_manifest_filepaths.map { |p| normalize_manifest_path_for_db(p) }
          manifests_scope = manifests_scope.where.not(
            "concat(coalesce(#{Manifest.table_name}.path, ''), '/', #{Manifest.table_name}.filename) IN (?)",
            normalized_manifest_paths
          )
        end

        manifests_by_id = manifests_scope
                            .select(:id, :manifest_type, :path, :filename, :last_pushed_at)
                            .map { |m| [m.id, m] }.to_h

        dependencies_rel =
          ManifestEntry.latest_revisions
                       .without_superseded_in_repository
                       .merge(manifests_scope)
                       .joins({ manifest_package_version: :manifest_package })

        if query.present?
          dependencies_rel = dependencies_rel.where(
            "#{ManifestPackage.table_name}.package_name LIKE ?",
            "%" + ActiveRecord::Base.sanitize_sql_like(query.downcase.strip) + "%"
          )
        end

        unless included_dependencies.nil?
          dependencies_rel = dependencies_rel.where_in(
            ["#{Manifest.table_name}.path", "#{Manifest.table_name}.filename", "#{ManifestPackage.table_name}.package_name", "#{ManifestPackageVersion.table_name}.requirements"],
            included_dependencies.map { |manifest_path, *rest| [*split_manifest_path(manifest_path), *rest] }
          )
        end

        unless excluded_dependencies.nil?
          dependencies_rel = dependencies_rel.where_not_in(
            ["#{Manifest.table_name}.path", "#{Manifest.table_name}.filename", "#{ManifestPackage.table_name}.package_name", "#{ManifestPackageVersion.table_name}.requirements"],
            excluded_dependencies.map { |manifest_path, *rest| [*split_manifest_path(manifest_path), *rest] }
          )
        end

        dependencies = dependencies_rel
                         .order(manifest_id: :asc, "#{ManifestPackage.table_name}.package_name": :asc, "#{ManifestPackageVersion.table_name}.requirements": :asc)
                         .select(:id, :manifest_id, :manifest_package_version_id, "#{ManifestPackage.table_name}.package_name", "#{ManifestPackageVersion.table_name}.requirements")

        if offset.present?
          dependencies = dependencies.offset(offset)
        end

        if limit.present?
          dependencies = dependencies.limit(limit)
        end

        ResultSet.new(
          total_results: dependencies_rel.count,
          package_managers: repo_package_managers,
          results: dependencies.map do |d|
            manifest = manifests_by_id[d.manifest_id]
            Result.new(
              package_manager: manifest.manifest_type.package_manager,
              package_name: d.package_name,
              requirements: d.requirements,
              manifest_path: manifest.full_path,
              scanned_by: :DG,
              scanned_at: manifest.last_pushed_at.utc
            )
          end
        )
      end

      def snapshot_manifests
        return @snapshot_manifests if defined?(@snapshot_manifests)
        relationship_filter = nil
        if @req.has_relationship_filter?
          relationship_filter = @req.relationship_filter
        end
        response = dependencies_client.get_dependencies_for_repository(@req.repository_id,
          include_internal_snapshots: false,
          include_root_ancestors: true,
          relationship_filter: relationship_filter
        )
        @snapshot_manifests = response.data.all_manifests.map do |manifest|
          DependencyGraph::ObjectModel::DSAPIManifest.new(manifest, response.data.snapshots[manifest.snapshot_id])
        end
      end

      def search_ds_dependencies(
        query:,
        offset: nil,
        limit: nil,
        included_dependencies: nil,
        excluded_dependencies: nil,
        manifest_path: nil,
        package_managers: []
      )
        all_manifest_paths = Set.new
        repo_package_managers = []

        results = snapshot_manifests.flat_map do |manifest|
          normalized_manifest_path = DependencyGraph::ObjectModel::AbstractManifest.normalize_manifest_path(manifest.file_path)
          if manifest_path.present?
            normalized_input_path = DependencyGraph::ObjectModel::AbstractManifest.normalize_manifest_path(manifest_path)
            next [] unless normalized_manifest_path == normalized_input_path
          end

          all_manifest_paths.add(normalized_manifest_path)

          manifest.dependencies.filter_map do |dependency|

            repo_package_managers << dependency.package_manager

            next unless package_managers&.include?(dependency.package_manager)

            result_values = {
              package_manager: dependency.package_manager,
              package_name: dependency.full_package_name,
              requirements: dependency.requirement_set.to_s,
              manifest_path: normalized_manifest_path,
              relationship: dependency.relationship.api_value,
              root_ancestors: dependency.root_ancestors,
              scanned_at: manifest.scanned,
              scanned_by: :DS,
              snapshot_detector_name: manifest.detector_name
            }

            if dependency.package_manager == Types::PackageManager[:unknown]
              result_values[:unsupported_package_manager_name] = dependency.package_url.package_manager_name
            end

            Result.new(**result_values)
          end
        end

        if query.present?
          results = results.filter { |r| r.package_name.downcase.include?(query.downcase.strip) }
        end

        unless included_dependencies.nil?
          results = results.filter do |r|
            included_dependencies
              .include?([r.manifest_path, r.package_name, r.requirements].map(&:downcase))
          end
        end

        unless excluded_dependencies.nil?
          results = results.filter do |r|
            excluded_dependencies
              .exclude?([r.manifest_path, r.package_name, r.requirements].map(&:downcase))
          end
        end

        total_results = results.length

        results = results.sort_by do |r|
          [r.manifest_path, r.package_name, r.requirements]
        end

        if offset.present?
          results = results[offset..] || []
        end

        if limit.present?
          results = results.slice(0, limit) || []
        end

        return ResultSet.new(
          total_results: total_results,
          results: results,
          package_managers: repo_package_managers.uniq,
          manifest_paths: all_manifest_paths
        )
      end

      def get_root_ancestors_for_dgp_dependencies(
        repository_id:,
        dependency_ids: []
      )
        if dependency_ids.empty?
          return {}
        end

        response = @dgp_insights_client.get_root_ancestors_for_dependencies(
          repository_id: repository_id,
          dependency_ids: dependency_ids
        )

        DependencyGraph.logger.info("Repo Insights DGP get_root_ancestors_for_dependencies response",
          response: response.data.to_json,
          "gh.repo.id": repository_id,
        )

        dependency_root_ancestors_map = if response&.data&.dependencies
                                          response.data.dependencies.each_with_object({}) do |dependency, map|
                                            map[dependency.id] = dependency.root_ancestors.map do |root_ancestor|
                                              {
                                                package_name: root_ancestor.package_name,
                                                requirements: root_ancestor.requirements,
                                                relationship: map_ancestor_relationship(root_ancestor.relationship),
                                              }
                                            end
                                          end
        else
          {}
        end

        dependency_root_ancestors_map
      end

      def split_manifest_path(manifest_path)
        filename = File.basename(manifest_path)
        path = if manifest_path == filename
                 ""
               else
                 File.dirname(manifest_path)
               end
        [path, filename]
      end

      private

      # normalize_manifest_path_for_db:
      #  - ./package.json -> /package.json
      #  - /package.json -> /package.json
      #  - /path/to/package.json -> path/to/package.json
      def normalize_manifest_path_for_db(full_path)
        os_normalized = ManifestAdapters.normalize_path(path: full_path)
        path, filename = split_manifest_path(os_normalized)
        # replace root with empty string, otherwise remove leading slashes
        path = path == "." || path == "/" ? "" : path.sub(/^\/+/, "")
        "#{path}/#{filename}"
      end

      def map_ancestor_relationship(relationship)
        case relationship
        when :ANCESTOR_RELATIONSHIP_PARENT
          DependencyGraphAPI::V1::SearchDependenciesForRepositoryResponse::AncestorRelationship::PARENT
        when :ANCESTOR_RELATIONSHIP_ANCESTOR
          DependencyGraphAPI::V1::SearchDependenciesForRepositoryResponse::AncestorRelationship::ANCESTOR
        else
          DependencyGraphAPI::V1::SearchDependenciesForRepositoryResponse::AncestorRelationship::UNKNOWN
        end
      end

      trace_method :sort_result_set
      def sort_result_set(result_set)
        dependabot_alerts_map = DependabotAlertsMap.new(@req.dependabot_alerts)

        result_set.sort_by do |result|
          severity_sort_key = severity_sort_key_from_dependabot_alerts(
            result.get_applicable_dependabot_alerts(dependabot_alerts_map)
          )
          [*severity_sort_key, result.manifest_path, result.package_name, result.requirements]
        end
      end

      def severity_sort_key_from_dependabot_alerts(dependabot_alerts)
        unless dependabot_alerts.present? && dependabot_alerts.any?
          return [0, 0]
        end

        highest_severity, highest_severity_count = dependabot_alerts
          .group_by(&:vulnerability_severity)
          .transform_keys(&DependencyGraphAPI::V1::Severity.method(:resolve))
          .transform_values(&:count)
          .max

        [-1 * highest_severity, -1 * highest_severity_count]
      end

      def dgp_vvrs_from_dependabot_alerts(dependabot_alerts:, package_managers:)
        dependabot_alerts.map { |dependabot_alert|
          dgp_vvr_from_dependabot_alert(dependabot_alert:, package_managers:)
        }.compact.uniq
      end

      def dgp_vvr_from_dependabot_alert(dependabot_alert:, package_managers:)
        manifest_type =
          begin
            ManifestAdapters.manifest_type(path: dependabot_alert.vulnerable_manifest_path)
          rescue ManifestAdapters::NotRecognizedError
            return nil
          end

        unless manifest_type.present? && !manifest_type.unknown?
          return nil
        end

        unless package_managers.include?(manifest_type.package_manager)
          return nil
        end

        unless manifest_type.package_manager.dgp_ecosystem.present?
          return nil
        end

        {
          id: dependabot_alert.vulnerable_version_range_id,
          affects: dependabot_alert.vulnerable_version_range_affects,
          requirements: dependabot_alert.vulnerable_version_range_requirements,
          ecosystem: manifest_type.package_manager.dgp_ecosystem
        }
      end

      def preview_enabled?
        @req.preview_enabled
      end

      def preview_manifest_type
        DependencyGraph::MANIFEST_TYPE_PREVIEW
      end

      def preview_package_manager
        DependencyGraph::PACKAGE_MANAGER_PREVIEW
      end

    end

    class Search
      class ResultSet
        attr_accessor :total_results,
          :results,
          :package_managers,
          :manifest_paths

        # We only care about manifest_paths coming from DS, and we only use that internally for deduplication.
        def initialize(total_results:, results:, package_managers:, manifest_paths: Set.new)
          @total_results = total_results
          @results = results
          @package_managers = package_managers
          @manifest_paths = manifest_paths
        end

        def self.empty
          return self.new(
            total_results: 0,
            results: [],
            package_managers: []
          )
        end

        def merge(other)
          return ResultSet.new(
            total_results: self.total_results + other.total_results,
            results: self.results + other.results,
            package_managers: (self.package_managers + other.package_managers).uniq,
            manifest_paths: self.manifest_paths + other.manifest_paths
          )
        end

        def sort_by(&block)
          return ResultSet.new(
            total_results: self.total_results,
            results: self.results.sort_by(&block),
            package_managers: self.package_managers
          )
        end

        def load_repository_ids
          package_refs = results.map { |r| [r.package_manager.to_i, r.package_name] }
          packages = Package
            .where_in(["package_manager", "name"], package_refs)
            .select(:package_manager, :name, :repository_id, :repository_id_certainty)

          results.each do |r|
            package = packages.find { |p| p.package_manager == r.package_manager && p.name == r.package_name }
            Instrument.increment("package_to_repo_mapping.viewed",
              package_manager: package.package_manager&.to_s.downcase || "unknown",
              certainty: package.repository_id_certainty || 0
            ) unless package.nil?
            r.repository_id = package&.repository_id
          end
        end

        def load_licenses
          # For results coming from DGP, don't attempt to load license. We
          # load licenses in DGP and assign them on the results already, so
          # we don't need to load them here.
          results_to_load_licenses_for = results.reject(&:scanned_by_dgp?)

          release_refs = results_to_load_licenses_for.filter_map do |result|
            if result.requirement_set.exact_version.present?
              [
                result.package_manager.to_i,
                result.package_name,
                # Hotfix: See PackageReleaseSearchAdapter for context
                PackageReleaseSearchAdapter.adapted_dependency_version(
                  result.package_manager,
                  result.requirement_set.exact_version
                )
              ]
            end
          end

          releases = PackageRelease
            .where_in(["package_manager", "package_name", "name"], release_refs)
            .select(:package_manager, :package_name, :name, :license)

          results_to_load_licenses_for.each do |result|
            next if result.scanned_by_dgp?
            release = releases.find do |release|
              release.package_manager == result.package_manager &&
                release.package_name.downcase == result.package_name.downcase &&
                  release.name == PackageReleaseSearchAdapter.adapted_dependency_version(
                    result.package_manager,
                    result.requirement_set.exact_version
                  )
            end
            result.license = release&.license
          end
        end

        def load_root_ancestors(
          root_ancestors: {}
        )
          results_to_load_root_ancestors_for = results.select(&:scanned_by_dgp?)

          results_to_load_root_ancestors_for.each do |result|
            result.root_ancestors = root_ancestors[result.id] || []
          end
        end
      end

      class Result
        attr_accessor :id,
          :package_manager,
          :package_name,
          :requirements,
          :manifest_path,
          :scope,
          :repository_id,
          :license,
          :scanned_by,
          :scanned_at,
          :snapshot_detector_name,
          :relationship,
          :vulnerable_version_range_ids,
          :root_ancestors,
          :unsupported_package_manager_name

        def initialize(
          id: nil,
          package_manager:,
          package_name:,
          requirements:,
          manifest_path:,
          scope: nil,
          scanned_by:,
          scanned_at: nil,
          snapshot_detector_name: nil,
          relationship: nil,
          vulnerable_version_range_ids: [],
          license: nil,
          root_ancestors: [],
          unsupported_package_manager_name: nil
        )
          @id = id
          @package_manager = package_manager
          @package_name = package_name
          @requirements = requirements
          @manifest_path = manifest_path
          @scope = scope
          @scanned_at = scanned_at
          @scanned_by = scanned_by
          @snapshot_detector_name = snapshot_detector_name
          @relationship = relationship
          @vulnerable_version_range_ids = vulnerable_version_range_ids || []
          @license = license
          @root_ancestors = root_ancestors
          @unsupported_package_manager_name = unsupported_package_manager_name
        end

        def scanned_by_dgp?
          scanned_by == :DGP
        end

        def get_applicable_dependabot_alerts(dependabot_alerts_map)
          if vulnerable_version_range_ids.present? && vulnerable_version_range_ids.any?
            # If we have vulnerable version range IDs, then use those to get the applicable alerts.
            vulnerable_version_range_ids.flat_map do |id|
              dependabot_alerts_map.get_alerts_by_path_and_id(manifest_path, id)
            end
          else
            # Otherwise, fall back on matching requirements.
            dependabot_alerts_map.get_alerts_by_path_affects_and_requirements(manifest_path, package_name, requirements)
          end
        end

        def requirement_set
          Versioning::RequirementSet.deserialize(requirements,
            allow_named_versions: Types::PackageManager.allows_named_versions?(package_manager)
          )
        end

        def to_proto
          DependencyGraphAPI::V1::SearchDependenciesForRepositoryResponse::Result.new(
            package_manager: package_manager.to_proto,
            package_name: package_name,
            requirements: requirements,
            manifest_path: manifest_path,
            scope: scope,
            repository_id: repository_id,
            license: license,
            scanned_at: scanned_at,
            scanned_by: scanned_by,
            snapshot_detector_name: snapshot_detector_name,
            relationship: relationship,
            vulnerable_version_range_ids: vulnerable_version_range_ids,
            root_ancestors: root_ancestors,
            unsupported_package_manager_name: unsupported_package_manager_name
          )
        end
      end

      class DependabotAlertsMap
        def initialize(dependabot_alerts)
          @alerts_by_path_and_id = Hash.new { |hash, key| hash[key] = [] }
          @alerts_by_path_affects_and_requirements = Hash.new { |hash, key| hash[key] = [] }

          dependabot_alerts.each do |da|
            key1 = [da.vulnerable_manifest_path.downcase, da.vulnerable_version_range_id]
            @alerts_by_path_and_id[key1] << da

            key2 = [da.vulnerable_manifest_path.downcase, da.vulnerable_version_range_affects.downcase, da.vulnerable_requirements.downcase]
            @alerts_by_path_affects_and_requirements[key2] << da
          end
        end

        def get_alerts_by_path_and_id(vulnerable_manifest_path, vulnerable_version_range_id)
          key = [vulnerable_manifest_path.downcase, vulnerable_version_range_id]
          @alerts_by_path_and_id[key]
        end

        def get_alerts_by_path_affects_and_requirements(vulnerable_manifest_path, vulnerable_version_range_affects, vulnerable_requirements)
          key = [vulnerable_manifest_path.downcase, vulnerable_version_range_affects.downcase, vulnerable_requirements.downcase]
          @alerts_by_path_affects_and_requirements[key]
        end
      end
    end
  end
end
