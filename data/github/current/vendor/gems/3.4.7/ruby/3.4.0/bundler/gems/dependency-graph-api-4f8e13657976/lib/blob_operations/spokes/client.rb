require "blob_operations/responses/responses_importer"
require "dependency_graph/faraday_client/internal_twirp_with_retries"
require "faraday_middleware/datadog"
require "faraday_middleware/resilient"
require "faraday"
require "spokes-proto"
require "dependency_graph/tracing"

module BlobOperations
  module Spokes
    class Client
      include DependencyGraph::Tracing

      SERVICE_NAME = "spokes"
      INSTRUMENTATION_PREFIX = "blob_operations.spokes.client".freeze

      attr_reader :config

      def initialize
        @config = Rails.application.config_for(:spokes).with_indifferent_access
      end

      trace_method :get_tree, span_attribute_extractor: -> (_instance, *_args, **kwargs) do
        {
          "gh.repo.id" => kwargs[:repository_id],
          "gh.push.commit_sha" => kwargs[:commit_id] || "",
        }
      end
      def get_tree(repository_id:, commit_id: nil, ref: nil, quality_of_service: nil)
        if commit_id.nil? && ref.nil?
          raise ArgumentError, "must supply either commit_id or ref"
        end

        repo = GitHub::Spokes::Proto::Types::V1::Repository.new(id: repository_id, type: :TYPE_REPOSITORY)
        oid = GitHub::Spokes::Proto::Types::V1::ObjectID.new(id: commit_id) if commit_id
        reference = GitHub::Spokes::Proto::Types::V1::Reference.new(name: ref) if ref

        treeish = if oid
                    GitHub::Spokes::Proto::Types::V1::Treeish.new(oid: oid)
                  else
                    GitHub::Spokes::Proto::Types::V1::Treeish.new(reference: reference)
                  end

        treeish_selector = GitHub::Spokes::Proto::Types::Selectors::V1::TreeishSelector.new(treeish: treeish)

        tree = fetch_full_trees_list(repository: repo, treeish_selector: treeish_selector, quality_of_service: quality_of_service)

        twirp_response = Twirp::ClientResp.new(data: tree)

        entries = tree.map do |entry|
          BlobOperations::Responses::TreeEntry.new(
            path: entry.path&.name,
            # mode should be an octal string to match legacy blob fetch behavior
            mode: entry.mode&.mode&.to_s(8),
            oid: entry.object&.oid&.id,
            repository_id: repository_id,
            blob_operations_provider: self,
          )
        end

        return BlobOperations::Responses::GetTree.new(twirp_response, tree_entries: entries)
      end

      trace_method :resolve_objects, span_attribute_extractor: -> (_instance, *_args, **kwargs) do
        {
          "gh.repo.id" => kwargs[:repository_id],
        }
      end
      def resolve_objects(repository_id:, object_selectors:)
        response = objects_client.resolve_objects(
          repository: {
            id: repository_id,
            type: :TYPE_REPOSITORY,
          },
          selectors: object_selectors
        )

        raise SpokesClientError.new(response.error.msg) if response.error

        return response.data.items
      end

      trace_method :fetch_full_trees_list, span_attribute_extractor: -> (_instance, *_args, **kwargs) do
        {
          "gh.repo.id" => kwargs[:repository]&.id,
        }
      end
      def fetch_full_trees_list(repository:, treeish_selector:, cursor: nil, trees: [], quality_of_service: nil)
        trees_response = trees_client.list_trees(
          repository: repository,
          treeish_selector: treeish_selector,
          recursive: true,
          cursor: cursor,
          request_context: {
            quality_of_service: quality_of_service
        })

        raise SpokesClientError.new(trees_response.error.msg) if trees_response.error

        t = trees.dup
        t.concat(trees_response.data.entries)

        if trees_response.data.next_cursor
          fetch_full_trees_list(
            repository: repository,
            treeish_selector: treeish_selector,
            cursor: trees_response.data.next_cursor,
            trees: t
          )
        else
          return t
        end
      end

      def read_diff_summary(repository_id:, base_oid:, target_oid:)
        Instrument.increment("#{INSTRUMENTATION_PREFIX}.requests.read_diff_summary")
        GitHub::Telemetry.tracer.in_span("spokes_provider.read_diff_summary") do
          repo = GitHub::Spokes::Proto::Types::V1::Repository.new(id: repository_id, type: :TYPE_REPOSITORY)
          base = GitHub::Spokes::Proto::Types::V1::ObjectID.new(id: base_oid)
          target = GitHub::Spokes::Proto::Types::V1::ObjectID.new(id: target_oid)
          begin
            diffs_client.read_diff_summary(repository: repo, object_id1: base, object_id2: target, diff_algorithm: GitHub::Spokes::Proto::Types::V1::DiffAlgorithm::DIFF_ALGORITHM_DEFAULT)
          rescue Faraday::TimeoutError
            Instrument.increment("#{INSTRUMENTATION_PREFIX}.requests.read_diff_summary.timeouts")
            DependencyGraph.logger.warn("read_diff_summary timeout",
              "gh.dependency_graph.blob_operations.provider" => SERVICE_NAME,
              "gh.repo.id" => repository_id,
              "gh.git.object_id1" => base_oid,
              "gh.git.object_id2" => target_oid,
            )
            raise
          rescue StandardError => e
            Instrument.increment("#{INSTRUMENTATION_PREFIX}.requests.read_diff_summary.errors")
            DependencyGraph.logger.error("read_diff_summary error",
              {
                "gh.dependency_graph.blob_operations.provider" => SERVICE_NAME,
                "gh.repo.id" => repository_id,
                "gh.git.object_id1" => base_oid,
                "gh.git.object_id2" => target_oid,
              },
              e
            )
            raise
          end
        end
      end

      trace_method :get_blob, span_attribute_extractor: -> (_instance, *_args, **kwargs) do
        {
          "gh.repo.id" => kwargs[:repository_id],
          "gh.git.content_oid" => kwargs[:oid],
        }
      end
      def get_blob(repository_id:, oid:)
        response = connection.get("/streaming/v1/repositories/#{repository_id}/blobs/#{oid}")
        if response.success?
          twirp_response = Twirp::ClientResp.new(data: response)
          BlobOperations::Responses::GetBlob.new(twirp_response,
            content: response.body,
            oid: oid,
            size_bytes: response.headers.nil? ? 0 : response.headers["Content-Length"])
        else
          twirp_error = Twirp::Error.new(Twirp::ERROR_CODES_TO_HTTP_STATUS.key(response.status), response.body)
          raise SpokesClientError.new(twirp_error)
        end
      end

      # object_exists checks whether an object exists in a given repo. Object can be a tag, branch or a SHA.
      def object_exists?(repository_id:, object:, quality_of_service: nil)
        if object.nil?
          raise ArgumentError, "must supply object which can be either a tag, branch or SHA"
        end

        repo = GitHub::Spokes::Proto::Types::V1::Repository.new(id: repository_id, type: :TYPE_REPOSITORY)
        object_name = GitHub::Spokes::Proto::Types::V1::Revision.new(name: object)

        request_context = { quality_of_service: quality_of_service }
        objects_response = objects_client.resolve_object(repository: repo, object_name: object_name, request_context: request_context)

        if objects_response.error
          if objects_response.error.code == :not_found
            return false
          else
            raise SpokesClientError.new(objects_response.error.msg)
          end
        else
          true
        end
      end

      private

      def trees_client
        @trees_client ||= GitHub::Spokes::Proto::Trees::V1::TreesAPIClient.new(connection)
      end

      def objects_client
        @objects_client ||= GitHub::Spokes::Proto::Objects::V1::ObjectsAPIClient.new(connection)
      end

      def diffs_client
        @diffs_client ||= GitHub::Spokes::Proto::Diffs::V2::DiffsAPIClient.new(connection)
      end

      def twirp_api_url
        @twirp_api_url ||= "#{config.fetch("base_uri")}/twirp"
      end

      def connection
        @connection ||= DependencyGraph::FaradayClient::InternalTwirpWithRetries.new(twirp_api_url, ssl: ::Spokes.certs) do |conn|
          conn.use GitHub::FaradayMiddleware::Datadog, stats: Rails.application.stats, service_name: SERVICE_NAME
          conn.use DependencyGraph::FaradayMiddleware::Resilient, name: SERVICE_NAME, options: {
            instrumenter: ActiveSupport::Notifications
          }
          conn.options[:open_timeout] = config.fetch("connection_open_timeout")
          conn.options[:timeout] = config.fetch("connection_read_timeout")
          conn.headers[:user_agent] = "dependency-graph-api spokes client"
        end
      end
    end

    class SpokesClientError < StandardError; end
  end
end
