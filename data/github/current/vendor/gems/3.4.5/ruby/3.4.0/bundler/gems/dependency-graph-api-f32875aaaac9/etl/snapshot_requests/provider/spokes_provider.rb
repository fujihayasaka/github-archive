require "faraday"

module SnapshotRequests
  module Provider
    class SpokesProvider < BlobOperationsProvider
      INSTRUMENTATION_PREFIX = "blob_operations.provider.spokes".freeze

      def name
        "spokes"
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
        begin
          return client.resolve_objects(repository_id: repository_id, object_selectors: object_selectors)
        rescue Faraday::TimeoutError
          Instrument.increment("#{INSTRUMENTATION_PREFIX}.requests.resolve_objects.timeouts")
          DependencyGraph.logger.warn("resolve_objects timeout",
            "gh.dependency_graph.blob_operations.provider" => name,
            "gh.repo.id" => repository_id,
          )
          raise
        rescue StandardError => e
          Instrument.increment("#{INSTRUMENTATION_PREFIX}.requests.resolve_objects.errors")
          DependencyGraph.logger.warn("resolve_objects error",
            {
              "gh.dependency_graph.blob_operations.provider" => name,
              "gh.repo.id" => repository_id,
            },
            e
          )
          raise
        end
      end

      private

      def client
        @client ||= BlobOperations::Spokes::Client.new
      end
    end
  end
end
