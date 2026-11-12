module SnapshotRequests
  module Provider
    class NoOpProvider < BlobOperationsProvider
      attr_accessor :get_blob_returns, :get_tree_returns

      # Public: Allows you to set values to return on calls, useful for testing:
      #   get_blob_returns: Hash of "blob data" to return on get_blob calls.
      #     Defaults to {}, expected to be key[OID]: value[BlobData]
      #   get_tree_returns: Array of "items" to return on get_tree calls. Defaults to []
      #
      def initialize(get_blob_returns: {}, get_tree_returns: [])
        self.get_blob_returns = get_blob_returns
        self.get_tree_returns = get_tree_returns
      end

      def name
        "no_op"
      end

      def get_tree(**args)
        GitHub::Telemetry.tracer.in_span("no_op_provider.get_tree") do
          DependencyGraph.logger.debug(
            "code.function" => "get_tree",
            "gh.dependency_graph.blob_operations.arguments" => args,
            "gh.dependency_graph.blob_operations.provider" => name
          )

          # Pretend that this is an actual response, and respond to the same "methods" that might be called on output.
          OpenStruct.new(tree_entries: get_tree_returns)
        end
      end

      def get_blob(repository_id: nil, oid: nil, **args)
        DependencyGraph.logger.debug(
          "code.function" => "get_blob",
          "gh.dependency_graph.blob_operations.arguments" => args,
          "gh.dependency_graph.blob_operations.provider" => name
        )

        get_blob_returns[oid]
      end
    end
  end
end
