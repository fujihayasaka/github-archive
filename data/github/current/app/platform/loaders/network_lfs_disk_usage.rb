# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class NetworkLfsDiskUsage < Platform::Loader
      def self.load(network_id)
        self.for.load(network_id)
      end

      def fetch(network_ids)
        ::Media::Blob.network_lfs_disk_usage(network_ids)
      end
    end
  end
end
