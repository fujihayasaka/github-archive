require "concurrent/promises"
require "dependency_graph/object_model/object_model"
require "dependency-graph-platform/repo_insights_client"
require "dependency-graph-platform/graphql_resolver_client"
require "dependency_snapshots_api/dependencies_client"
require "monolith/features"

module RepositoryDependenciesService
  module V1
    class Handler < TracedHandler
      include DependencyGraph::Tracing

      DEFAULT_MAX_STATIC_MANIFESTS = 150

      def initialize(dependencies_client: default_dependencies_client,
          dgp_insights_client: default_dgp_insights_client,
          dgp_graphql_resolver_client: default_dgp_graphql_resolver_client,
          blob_operations_provider: default_operations_provider)
        @dependencies_client = dependencies_client
        @dgp_insights_client = dgp_insights_client
        @dgp_graphql_resolver_client = dgp_graphql_resolver_client
        @blob_operations_provider = blob_operations_provider
      end

      def search_dependencies_for_repository(req, env)
        repo = Repository.find_by(github_repository_id: req.repository_id)

        trace(
          github_repository_id: req.repository_id,
          nwo: repo&.nwo
        ) do
          search = Search.new(req, dependencies_client:, dgp_insights_client:)
          result_set = search.run

          return DependencyGraphAPI::V1::SearchDependenciesForRepositoryResponse.new(
            total_results: result_set.total_results,
            results: result_set.results.map(&:to_proto),
            package_managers: result_set.package_managers.map(&:to_proto).sort,
            repository_has_snapshots: search.repository_has_snapshots
          )
        end
      end

      def get_dependencies_for_repository(req, env)
        trace(
          **get_tracing_payload_from_request(req)
        ) do
          snapshot_dependencies = Concurrent::Promises.future do
            # Return early if snapshots are disabled or circuit-broken
            next [] unless DependencyGraphAPI.snapshots_enabled?

            get_dependency_snapshot_dependencies(req, req.repository_id)
          end

          static_manifests = get_static_manifest_dependencies(req)
          next static_manifests if static_manifests.instance_of? Twirp::Error

          snap_manifests = snapshot_dependencies.value!
          next snap_manifests if snap_manifests.instance_of? Twirp::Error

          manifests_or_twirp_error = snap_manifests + static_manifests

          # At this point, all possible cases where manifests_or_twirp_error could've been error have been previously returned,
          # so we're just setting manifests.
          DependencyGraphAPI::V1::GetDependenciesForRepositoryResponse.new(manifests: manifests_or_twirp_error)
        end
      end

      def repositories_containing_dependency(req, env)
        trace(
          base_purl: req.base_purl,
          version_range: req.version_range
        ) do
          if !DependencyGraphAPI.snapshots_enabled?
            return DependencyGraphAPI::V1::RepositoriesContainingDependencyResponse.new(repository_ids: [])
          end

          return get_repositories_from_api(req)
        end
      end

      def has_manifests(req, env)
        trace(
          github_repository_id: req.repository_id
        ) do

          return Twirp::Error.new(:invalid_argument, "Repository not supplied") unless is_property_present(obj: req, symbol: :repository_id)

          repository = find_by_github_repo_id(req.repository_id, "repository_id", {})

          has_static_manifests = false
          if repository.present?
            has_static_manifests = Manifest.where(repository_id: repository.id).exists?
          end

          # Return early if we have static manifests to avoid making further calls
          return DependencyGraphAPI::V1::HasManifestsResponse.new(
            has_manifests: true,
          ) if has_static_manifests

          has_dgp_manifests = false
          should_check_dgp = dgp_resolver_enabled?(req.repository_id, repository&.github_owner_id)
          if should_check_dgp
            response = dgp_graphql_resolver_client.repository_has_manifests(repository_id: req.repository_id)
            if response.error.present?
              DependencyGraph.logger.error("Outbound call to dgp-graphql-resolver failed",
                "exception.message" => response.error.to_s[..500],
                "code.function" => "repository_has_manifests",
                "code.namespace" => self.class.name,
              )
              return Twirp::Error.new(response.error.code, response.error.msg, response.error.meta)
            else
              has_dgp_manifests = response.data.has_manifests
            end
          end

          # Return early if we have dgp manifests to avoid making a call to DS API
          return DependencyGraphAPI::V1::HasManifestsResponse.new(
            has_manifests: true,
          ) if has_dgp_manifests

          should_check_snapshots = DependencyGraphAPI.snapshots_enabled? && !req.only_static_manifests
          has_snapshot_manifests = false
          if should_check_snapshots
            response = dependencies_client.has_manifests(req.repository_id)
            if response.error.present?
              DependencyGraph.logger.error("Outbound call to ds-api returned an error",
                "exception.message" => response.error.to_s[..500],
                "code.function" => "has_manifests",
                "code.namespace" => self.class.name,
              )
              return Twirp::Error.new(response.error.code, response.error.msg, response.error.meta)
            else
              has_snapshot_manifests = response.data.has_manifests
            end
          elsif !repository.present? && !should_check_dgp
            # This means we couldn't check for static manifests either!
            return Twirp::Error.new(:not_found, "Repository not found")
          end

          DependencyGraphAPI::V1::HasManifestsResponse.new(
            has_manifests: has_snapshot_manifests,
          )
        end
      end

      add_log_context :get_dependencies_for_repository
      add_log_context :has_manifests

      private

      attr_reader :dependencies_client
      attr_reader :dgp_insights_client
      attr_reader :dgp_graphql_resolver_client
      attr_reader :blob_operations_provider

      def default_dependencies_client
        DependencyGraphAPI::DependencySnapshotsAPI::DependenciesClient.new
      end

      def default_dgp_insights_client
        DependencyGraphAPI::DependencyGraphPlatform::RepoInsightsClient.new
      end

      def default_dgp_graphql_resolver_client
        DependencyGraphAPI::DependencyGraphPlatform::GraphQLResolverClient.new
      end

      def default_operations_provider
        SnapshotRequests::Provider::SpokesProvider.new
      end

      def get_dependency_snapshot_dependencies(req, github_repository_id)
        response = dependencies_client.get_dependencies_for_repository(
          github_repository_id,
          include_internal_snapshots: (req.include_internal_snapshots || false),
        )
        if response.error.present?
          # TODO: Real error handling, this is here mostly to make sure we clearly fail when surprised.
          DependencyGraph.logger.error("Outbound call to d-s-api failed",
                                       "exception.message" => response.error.to_s[..500],
                                        **get_tracing_payload_from_request(req).merge!({}))
          return Twirp::Error.internal("An unexpected error occurred during snapshot retrieval")
        end

        manifests = DependencyGraph::ObjectModel::DSAPIManifest.collapse_ds_api_manifests(response.data.all_manifests)
        proto_manifests = DependencyGraph::ObjectModel::AbstractManifest.to_proto(
          manifests: manifests,
          lookup_vulnerabilities: true,
          include_relationship: ds_transitive_labels_enabled?(github_repository_id)
        )
      end

      def get_repositories_from_api(req)
        response = dependencies_client.repositories_containing_dependency(req.base_purl, req.version_range)
        if response.error.present?
          # TODO: Real error handling, this is here mostly to make sure we clearly fail when surprised.
          DependencyGraph.logger.error("Outbound call to ds-api failed",
                                       "exception.message" => response.error.to_s[..500],
                                       "gh.dependency_graph.snapshot.query.base_purl" => req.base_purl,
                                       "gh.dependency_graph.snapshot.query.version_range" => req.version_range)
          return Twirp::Error.new(response.error.code, response.error.msg, response.error.meta)
        end
        DependencyGraphAPI::V1::RepositoriesContainingDependencyResponse.new(repository_ids: response.data.repository_ids.to_a)
      end

      def get_tracing_payload_from_request(req)
        {
          "gh.repo.id" => req.repository_id,
          "gh.dependency_graph.query.include_vulnerabilities" => req.include_vulnerabilities,
          "gh.dependency_graph.query.enable_preview_ecosystems" => req.enable_preview_ecosystems,
        }
      end

      trace_method :get_static_manifest_dependencies
      # Private: Find static manifests in this repository at a SHA and then output the dependencies with vulnerabilities.
      #
      # Returns GetDependenciesForRepositoryResponse
      def get_static_manifest_dependencies(req)
        # Do this conversion up top to reduce duplication
        exclude_package_managers = req.exclude_ecosystems.map { |ecosystem| Types::PackageManager.from_proto(ecosystem) }

        # DG currently doesn't store this info per sha, so someone specifying a sha is treated as "special": they want
        # a dynamically parsed set of manifests at a specific commit.
        if req.sha.present?
          repo_actor = FeatureFlags::Actor::Repository.new(req.repository_id)
          if DependencyGraph.flipper[:dependency_graph_get_dependencies_for_repository_ignore_sha].enabled?(repo_actor)
            DependencyGraph.logger.info("Ignoring SHA for GetDependenciesForRepository", **get_tracing_payload_from_request(req))
            # Ignoring SHA. Highly tactical solution to timeouts, see https://github.com/github/dependency-graph/issues/3612
            # for rationale and explanation for the `sleep`.
            sleep(30.seconds)
            return manifests_for_repository_from_db(
              req.repository_id,
              preview_enabled: req.enable_preview_ecosystems,
              exclude_package_managers: exclude_package_managers
            )
          elsif DependencyGraph.flipper[:dependency_graph_faster_get_dependencies_for_repository].enabled?(repo_actor)
            return Instrument.time_dist("repository_dependencies_service.faster_dynamically_parsed_manifests_for_repository") do
              faster_dynamically_parsed_manifests_for_repository(
                req.repository_id,
                sha: req.sha,
                max_static_manifests: req.max_static_manifests,
                preview_enabled: req.enable_preview_ecosystems,
                exclude_package_managers: exclude_package_managers
              )
            end
          else
            return Instrument.time_dist("repository_dependencies_service.dynamically_parsed_manifests_for_repository") do
              dynamically_parsed_manifests_for_repository(
                req.repository_id,
                sha: req.sha,
                max_static_manifests: req.max_static_manifests,
                preview_enabled: req.enable_preview_ecosystems,
                exclude_package_managers: exclude_package_managers
              )
            end
          end
        else
          return manifests_for_repository_from_db(
            req.repository_id,
            preview_enabled: req.enable_preview_ecosystems,
            exclude_package_managers: exclude_package_managers)
        end
      rescue BlobOperations::Spokes::SpokesClientError => e
        if e.message == "object_id.id must be a valid object id"
          return Twirp::Error.new(:not_found, "SHA not found")
        else
          # Since we don't know this error, raise again and output the default message.
          raise e
        end
      end

      trace_method :manifests_for_repository_from_db
      # Private: Get manifest contents from DB, lookup vulns, and return.
      #
      # Returns Array of DependencyGraphAPI::V1::Manifest objects
      def manifests_for_repository_from_db(github_repository_id, preview_enabled: false, exclude_package_managers: [])
        repository = Repository.find_by(github_repository_id: github_repository_id)
        return [] unless repository

        db_manifests = db_filtered_manifests(repository, preview_enabled, exclude_package_managers)

        manifests = db_manifests.map { |m| DependencyGraph::ObjectModel::DBManifest.new(m) }

        DependencyGraph::ObjectModel::AbstractManifest.to_proto(manifests: manifests, lookup_vulnerabilities: true)
      end

      trace_method :dynamically_parsed_manifests_for_repository, span_attribute_extractor: -> (_instance, *args, **kwargs) do
        {
          "gh.repo.id" => args[0],
          "gh.push.commit_sha" => kwargs[:sha],
        }
      end
      # Private: Find and parse Manifests in a Repository at a SHA using Spokes, lookup vulns, and return.
      #
      # Returns Array of DependencyGraphAPI::V1::Manifest objects
      def dynamically_parsed_manifests_for_repository(github_repository_id, sha:, preview_enabled: false, max_static_manifests: 0, exclude_package_managers: [])
        max_static_manifests = max_static_manifests == 0 ? DEFAULT_MAX_STATIC_MANIFESTS : max_static_manifests
        dotcom_tree_entries = blob_operations_provider.manifest_tree_entries_at_sha(github_repository_id, sha)
        # Sort tree entries according depth of folders they are in. This sort is mainly here to match how
        # dotcom previously sorted these entries, and it doesn't seem too unintuitive.
        dotcom_tree_entries = dotcom_tree_entries.sort_by { |entry| [entry.path.count("/"), entry.path] }

        blobs_by_oid = {}

        dotcom_tree_entries.each do |tree_entry|
          next if VendorDetection.vendored_manifest_path?(tree_entry.path)
          blobs_by_oid[tree_entry.oid] = tree_entry.get_blob!.content
        end

        parsed_manifests = []
        dotcom_tree_entries.each do |tree_entry|
          next if VendorDetection.vendored_manifest_path?(tree_entry.path)

          blob = blobs_by_oid[tree_entry.oid]

          # Facts: Git is not guaranteed to have UTF_8 compliant paths. Spokes needs to send these across the wire,
          # which is with the 'bytes' protobuf type. Ruby approximates bytes as ASCII_8BIT (think of this as byte array / byte string).
          # What we did: Assume the path is valid and force UTF_8 encoding. This could still result in
          # conversion errors but should mitigate issues we see with ones that are actually valid UTF8. If you do this:
          #   "\xF0\x9F\x99\x82/package.json".force_encoding(Encoding::ASCII_8BIT).encode(Encoding::UTF_8)
          # you'll see the error we're heading off (this is valid UTF_8 stored in ASCII_8BIT).
          corrected_tree_entry_path = tree_entry.path.dup.force_encoding(Encoding::UTF_8)
          if !corrected_tree_entry_path.valid_encoding?
            DependencyGraph.logger.error("Invalid encoded manifest path. Skipping this manifest.",
                                         "gh.dependency_graph.manifest.invalid_path" => tree_entry.path)
            next
          end

          manifest = ParsedManifest.new(
            content: blob,
            filename: File.basename(corrected_tree_entry_path),
            path: File.dirname(corrected_tree_entry_path),
            github_repository_id: github_repository_id,
          )

          if exclude_manifest?(manifest, preview_enabled, exclude_package_managers)
            # don't add this
          else
            parsed_manifests.push(DependencyGraph::ObjectModel::ParsedManifest.new(manifest))
          end

          break if parsed_manifests.count >= max_static_manifests
        end

        DependencyGraph::ObjectModel::AbstractManifest.to_proto(manifests: parsed_manifests, lookup_vulnerabilities: true)
      end

       # Private: Find and parse Manifests in a Repository at a SHA using Spokes, lookup vulns, and return.
      #
      # Returns Array of DependencyGraphAPI::V1::Manifest objects
      trace_method :faster_dynamically_parsed_manifests_for_repository
      def faster_dynamically_parsed_manifests_for_repository(github_repository_id, sha:, preview_enabled: false, max_static_manifests: 0, exclude_package_managers: [])
        max_static_manifests = max_static_manifests == 0 ? DEFAULT_MAX_STATIC_MANIFESTS : max_static_manifests
        dotcom_tree_entries = blob_operations_provider.manifest_tree_entries_at_sha(github_repository_id, sha)
        # Sort tree entries according depth of folders they are in. This sort is mainly here to match how
        # dotcom previously sorted these entries, and it doesn't seem too unintuitive.
        dotcom_tree_entries = dotcom_tree_entries.sort_by { |entry| [entry.path.count("/"), entry.path] }

        # Get what we've got in the DB
        repository = Repository.find_by(github_repository_id: github_repository_id)
        db_manifests = db_filtered_manifests(repository, preview_enabled, exclude_package_managers)

        # Since we heavily throttle writes when ingesting a manifest, we don't want to use
        # manifests that have been recently updated as they might still be in the middle of writes.
        # The 30 seconds window is arbitrary and probably over-pessimistic, but that's what I chose.
        db_manifests = db_manifests.where("#{Manifest.table_name}.updated_at < ?", 30.seconds.ago)

        # Get blob OIDs
        db_manifest_by_oid = {}
        object_selectors = db_manifests.map do |m|
          {
            by_treeish_and_path: {
              treeish: { oid: { id: m.latest_git_ref } },
              path: { name: m.full_path }
            }
          }
        end
        resolved_objects = blob_operations_provider.resolve_objects(
          repository_id: github_repository_id,
          object_selectors: object_selectors
        )

        db_manifests.zip(resolved_objects).each do |db_manifest, resolved_object|
          if resolved_object.object.present?
            db_manifest_by_oid[resolved_object.object.oid.id] = db_manifest
          end
        end

        parsed_manifests = []
        dotcom_tree_entries.each do |tree_entry|
          next if VendorDetection.vendored_manifest_path?(tree_entry.path)


          # If we already got a DB manifest, just return that yo
          if db_manifest_by_oid.key?(tree_entry.oid)
            m = db_manifest_by_oid[tree_entry.oid]
            m.path = "." if m.path.blank?
            parsed_manifests.push(DependencyGraph::ObjectModel::DBManifest.new(m))
            next
          end

          blob = tree_entry.get_blob!.content

          # Facts: Git is not guaranteed to have UTF_8 compliant paths. Spokes needs to send these across the wire,
          # which is with the 'bytes' protobuf type. Ruby approximates bytes as ASCII_8BIT (think of this as byte array / byte string).
          # What we did: Assume the path is valid and force UTF_8 encoding. This could still result in
          # conversion errors but should mitigate issues we see with ones that are actually valid UTF8. If you do this:
          #   "\xF0\x9F\x99\x82/package.json".force_encoding(Encoding::ASCII_8BIT).encode(Encoding::UTF_8)
          # you'll see the error we're heading off (this is valid UTF_8 stored in ASCII_8BIT).
          corrected_tree_entry_path = tree_entry.path.dup.force_encoding(Encoding::UTF_8)
          if !corrected_tree_entry_path.valid_encoding?
            DependencyGraph.logger.error("Invalid encoded manifest path. Skipping this manifest.",
                                         "gh.dependency_graph.manifest.invalid_path" => tree_entry.path)
            next
          end

          manifest = ParsedManifest.new(
            content: blob,
            filename: File.basename(corrected_tree_entry_path),
            path: File.dirname(corrected_tree_entry_path),
            github_repository_id: github_repository_id,
          )

          # If the manifest is in preview, and returning preview isn't enabled, don't return the manifest.
          if manifest.in_preview? && !preview_enabled
            # don't add this, we're not preview_enabled
          else
            parsed_manifests.push(DependencyGraph::ObjectModel::ParsedManifest.new(manifest))
          end

          break if parsed_manifests.count >= max_static_manifests
        end

        DependencyGraph::ObjectModel::AbstractManifest.to_proto(manifests: parsed_manifests, lookup_vulnerabilities: true)
      end

      def dgp_resolver_enabled?(repository_id, owner_id)
        (!owner_id.nil? && DependencyGraph.flipper[:dependency_graph_dgp_backed_npm_graphql]
                                            .enabled?(FeatureFlags::Actor::User.new(owner_id))) ||
          DependencyGraph.flipper[:dependency_graph_dgp_backed_npm_graphql].enabled?(FeatureFlags::Actor::Repository.new(repository_id))
      end

      def exclude_manifest?(manifest, preview_enabled, exclude_package_managers)
        # If the manifest is in preview, and returning preview isn't enabled, don't return the manifest.
        return true if manifest.in_preview? && !preview_enabled
        # If the package manager is supplied by DGP, don't return the manifest
        return true if exclude_package_managers.include?(manifest.package_manager)

        false
      end

      def db_filtered_manifests(repository, preview_enabled, exclude_package_managers)
        # Assume things like max manifests was enforced at DB data entry time, just return what's in the DB.
        db_manifests = if DependencyGraph.use_normalized_tables?
                         Manifest.includes(entries: { manifest_package_version: :manifest_package })
                           .references(entries: { manifest_package_version: :manifest_package })
                           .where(repository_id: repository.id)
                           .where("#{::ManifestEntry.table_name}.last_seen_at_revision = #{Manifest.table_name}.revision")
                       else
                         Manifest.includes(:dependencies).references(:dependencies)
                           .where(repository_id: repository.id)
                           .where("#{ManifestDependency.table_name}.last_seen_at_revision = #{Manifest.table_name}.revision")
                       end

        # Exclude package managers passed in, which are being pulled from DGP
        unless exclude_package_managers.empty?
          db_manifests = db_manifests.where.not(package_manager: exclude_package_managers)
        end

        # Exclude manifests that are marked as "preview" unless preview is enabled
        unless preview_enabled
          db_manifests = db_manifests
            .where.not(manifest_type: DependencyGraph::MANIFEST_TYPE_PREVIEW)
            .where.not(package_manager: DependencyGraph::PACKAGE_MANAGER_PREVIEW)
        end

        db_manifests
      end

      def ds_transitive_labels_enabled?(repository_id)
        @ds_transitive_labels_enabled ||= DependencyGraph.flipper[:dependency_graph_snapshot_transitive_labels].enabled?(FeatureFlags::Actor::Repository.new(repository_id))
      end
    end
  end
end
