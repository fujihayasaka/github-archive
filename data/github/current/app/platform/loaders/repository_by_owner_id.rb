# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class RepositoryByOwnerId < Platform::Loader
      def self.load(network_id, owner_id)
        self.for(network_id).load(owner_id)
      end

      def self.load_all(network_id, owner_ids)
        loader = self.for(network_id)
        Promise.all(owner_ids.map { |owner_id| loader.load(owner_id) })
      end

      def initialize(network_id)
        @network_id = network_id
      end

      def fetch(owner_ids)
        ::Repository
          .where(source_id: @network_id, owner_id: owner_ids)
          .index_by(&:owner_id)
      end
    end
  end
end
