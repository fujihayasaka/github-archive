# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class RepositoryNetworkById < Platform::Loader
      def self.load(network_id)
        self.for.load(network_id)
      end

      def self.load_many(network_ids)
        self.for.load_many(network_ids)
      end

      def fetch(network_ids)
        RepositoryNetwork.where(id: network_ids).includes(:children).index_by(&:id)
      end
    end
  end
end
