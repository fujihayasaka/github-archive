require "faraday"

module SnapshotRequests
  module Provider
    class SpokesProvider < BlobOperationsProvider
      INSTRUMENTATION_PREFIX = "blob_operations.provider.spokes".freeze

      # Spokes API has a limit of 1000 selectors per request
      MAX_SELECTORS_PER_REQUEST = 1000

      def name
        "spokes"
      end

      def spokes_delta_to_path(d)
        if d.delta.diff_status == :DIFF_STATUS_ADDITION
          return d.delta.new_tree_node.path.name.dup.force_encoding("UTF-8")
        else
          return d.delta.old_tree_node.path.name.dup.force_encoding("UTF-8")
        end
      end

      def get_changed_manifests(repository_id:, base_oid:, target_oid:)
        Instrument.increment("#{INSTRUMENTATION_PREFIX}.requests.get_changed_manifests")
        GitHub::Telemetry.tracer.in_span("spokes_provider.get_changed_manifests") do
          begin
            base = []
            target = []
            summary = client.read_diff_summary(repository_id: repository_id, base_oid: base_oid, target_oid: target_oid)
            if summary.error
              raise BlobOperations::Spokes::SpokesClientError.new(summary.error)
            end
            deltas = summary.data.deltas
            deltas.each do |d|
              path = spokes_delta_to_path(d)
              unless ManifestAdapters.recognized_path?(path: path)
                next
              end
              unless d.delta.diff_status == :DIFF_STATUS_ADDITION
                base.push({ path: path, blob_id: d.delta.old_tree_node.object.oid.id })
              end
              unless d.delta.diff_status == :DIFF_STATUS_DELETION
                target.push({ path: path, blob_id: d.delta.new_tree_node.object.oid.id })
              end
            end
            [base, target]
          end
        end
      end

      def get_tree(repository_id:, commit_id: nil, ref: nil, quality_of_service: nil)
        Instrument.increment("#{INSTRUMENTATION_PREFIX}.requests.get_tree")
        GitHub::Telemetry.tracer.in_span("spokes_provider.get_tree") do
          begin
            client_response = client.get_tree(repository_id: repository_id, commit_id: commit_id, ref: ref, quality_of_service: quality_of_service)
          rescue Faraday::TimeoutError
            Instrument.increment("#{INSTRUMENTATION_PREFIX}.requests.get_tree.timeouts")
            DependencyGraph.logger.warn("get_tree timeout",
              "gh.dependency_graph.blob_operations.provider" => name,
              "gh.repo.id" => repository_id,
              "gh.commit.sha" => commit_id,
              "gh.git.ref" => ref,
            )
            raise
          rescue StandardError => e
            Instrument.increment("#{INSTRUMENTATION_PREFIX}.requests.get_tree.errors")
            DependencyGraph.logger.error("get_tree error",
              {
                "gh.dependency_graph.blob_operations.provider" => name,
                "gh.repo.id" => repository_id,
                "gh.commit.sha" => commit_id,
                "gh.git.ref" => ref,
              },
              e
            )
            raise
          end
        end
      end

      def get_blob(repository_id:, oid:)
        Instrument.increment("#{INSTRUMENTATION_PREFIX}.requests.get_blob")
        begin
          client.get_blob(repository_id: repository_id, oid: oid)
        rescue Faraday::TimeoutError
          Instrument.increment("#{INSTRUMENTATION_PREFIX}.requests.get_blob.timeouts")
          DependencyGraph.logger.warn("get_blob timeout",
            "gh.dependency_graph.blob_operations.provider" => name,
            "gh.repo.id" => repository_id,
            "gh.git.oid" => oid,
          )
          raise
        rescue StandardError => e
          Instrument.increment("#{INSTRUMENTATION_PREFIX}.requests.get_blob.errors")
          DependencyGraph.logger.warn("get_blob error",
            {
              "gh.dependency_graph.blob_operations.provider" => name,
              "gh.repo.id" => repository_id,
              "gh.git.oid" => oid,
            },
            e
          )
          raise
        end
      end

      def resolve_objects(repository_id:, object_selectors:)
        Instrument.increment("#{INSTRUMENTATION_PREFIX}.requests.resolve_objects")
        DependencyGraph.logger.with_named_tags(
          {
            "gh.repo.id" => repository_id,
            "gh.dependency_graph.blob_operations.provider" => name,
            "gh.dependency_graph.blob_operations.selectors_size" => object_selectors.size,
            "gh.dependency_graph.blob_operations.max_selectors" => MAX_SELECTORS_PER_REQUEST,
          }
        ) do
          begin
            DependencyGraph.logger.info("calling spokes to resolve objects in batches")

            # We raise an error if object_selectors is empty to use for retrying
            raise BlobOperations::Spokes::SpokesClientError, "selectors is required" if object_selectors.empty?

            items = []
            # we batch calls bc Spokes API will return an error if the selectors exceed the maximum allowed size
            object_selectors.each_slice(MAX_SELECTORS_PER_REQUEST) do |selectors|
              results = client.resolve_objects(repository_id: repository_id, object_selectors: selectors)
              items.concat(results)
            end
            Instrument.count("#{INSTRUMENTATION_PREFIX}.requests.resolve_objects.resolved_objects", items.size)
            items
          rescue Faraday::TimeoutError
            Instrument.increment("#{INSTRUMENTATION_PREFIX}.requests.resolve_objects.timeouts")
            DependencyGraph.logger.warn("resolve_objects timeout")
            raise
          rescue StandardError => e
            Instrument.increment("#{INSTRUMENTATION_PREFIX}.requests.resolve_objects.errors")
            DependencyGraph.logger.warn("resolve_objects error", e)
            raise
          end
        end
      end

      private

      def client
        @client ||= BlobOperations::Spokes::Client.new
      end
    end
  end
end
