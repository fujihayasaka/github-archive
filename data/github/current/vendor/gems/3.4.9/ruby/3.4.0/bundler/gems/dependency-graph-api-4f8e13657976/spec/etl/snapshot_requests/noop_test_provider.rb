require_relative "../../../etl/snapshot_requests/provider/blob_operations_provider"

module SnapshotRequests::Provider
  class NoOpTestProvider < BlobOperationsProvider
    def name
      "NoOpTestProvider"
    end

    def get_tree(**args)
    end

    def get_blob(**args)
    end

    def get_changed_manifests(**args)
    end
  end
end
